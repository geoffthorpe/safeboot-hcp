#!/usr/bin/python3

### Initial code is common between qemu/runner.py and uml/runner.py

# Usage: runner.py <workload> [args...]

# This script runs inside the 'qemu_runner' container and takes care of running
# the QEMU instance. It should not be confused with code running inside the
# QEMU instance.
# Expectations: we are started via launcher, with a JSON config whose 'runner'
# section may contain an 'init_env' section. We also expect the following
# mounts;
#   - /hostfs/usecase
#   - /hostfs/fqdn-bus
# Before starting the QEMU instance, we;
#   - prepare /hostfs/config.json;
#       {
#         "HCP_CONFIG_FILE": "/hostfs/usecase/{workload}.json",
#         "argv": [ args... ],
#         "init_env": { ... },
#         "mounts": { ... }
#       }
#     - 'HCP_CONFIG_FILE' points to the usecase corresponding to <workload>,
#     - 'argv' contains any remaining cmd-line "args...",
#     - 'init_env' is passed along from the 'runner' JSON input, if it exists.
#   - we start vde_switch in the container (at /vdeswitch)
#   - we start slirpvde in the container (plugged into /vdeswitch)

import os
import sys
import json
import shutil
import subprocess
import tempfile
import socket

sys.path.insert(1, '/hcp/common')
import hcp_common as h

# Process cmd-line
workload = None
if 'HCP_CONFIG_FILE' in os.environ:
	workload = os.environ['HCP_CONFIG_FILE']
sys.argv.pop(0)
if len(sys.argv) > 1:
	workload = sys.argv.pop(0)
print(f"qemu runner launching workload: {workload}", file=sys.stderr)

# Get a temporary directory for our /hostfs mount
hostfs_dir = tempfile.mkdtemp()

# Prepare the JSON-encoded config
hostfs_config = f"{hostfs_dir}/config.json"
config = {
	'HCP_CONFIG_FILE': workload,
	'argv': sys.argv
}
init_env = h.hcp_config_extract('runner.init_env', or_default = True)
if init_env:
	config['init_env'] = init_env
mounts = h.hcp_config_extract('runner.mounts', or_default = True)
if mounts:
	config['mounts'] = mounts
slirp = h.hcp_config_extract('runner.slirp', or_default = True)
# This one is interesting, because we're taking a prop from fqdn_updater,
# rather than runner. This avoids us having to tweak and relocate the 'usecase'
# JSON to inject the container networks into the fqdn_updater that will run
# inside the VM. We simply embed it in the config JSON here, and the
# fqdn_updater instance in the VM will look out for it.
publish_networks = h.hcp_config_extract('fqdn_updater.publish_networks',
					or_default = True)
if publish_networks:
	# TODO: we're taking the fqdn_updater's path, which is in the container,
	# and we're passing it to the fqdn_updater running in the VM, which will
	# use it as a path there too. Not a general solution.
	config['publish_networks'] = publish_networks

# If we're instructed to put our drive state somewhere, do so. This is
# in order to support persistence.
state = h.hcp_config_extract('runner.state', or_default = True)
if not state:
	state = tempfile.mkdtemp()

# Dump config (HCP_CONFIG_FILE, **argv, mounts) as JSON for the guest
with open(hostfs_config, 'w') as fp:
	json.dump(config, fp)

def run(cmd):
	print(f"{cmd}", file = sys.stderr)
	subprocess.run(cmd)

# Start up a VDE switch and plug a slirpvde instance into it (for DHCP, DNS,
# and router). Note, we no longer build vde2 tooling from source, as we have at
# least one HCP_VARIANT (bullseye) that can has usable tooling in its upstream
# packages. But if it gets re-enabled, the call to 'vde_switch' must be
# replaced with '/usr/legacy/bin/vde_switch'.
run("vde_switch -d -s /vdeswitch -M /vdeswitch_mgmt".split())
# TODO: need to make all this configurable;
slirpcmd = [ 'vde_plug', '--daemon', 'vde:///vdeswitch' ]
slirparg = 'slirp:///dhcp=10.0.2.15/vnameserver=10.0.2.3'
if slirp:
	if not isinstance(slirp, dict):
		h.bail(f"'runner.slirp' must be dict (not {type(slirp)})")
	ports = []
	if 'ports' in slirp:
		ports = slirp['ports']
		if not isinstance(ports, list):
			h.bail(f"'runner.slirp.ports' must be list (not {type(ports)})")
	# TODO: it's not clear how to be certain of the address the VM will
	# get, other than it's the first (only) DHCP client and by default the
	# DHCP server (apparently) hands out addresses from 10.0.2.15 onwards.
	# <shrug>
	vdehost = '10.0.2.15'
	tcpfwd=''
	for p in ports:
		n = f"{p}:{vdehost}:{p}"
		if len(tcpfwd) > 0:
			tcpfwd = f"{tcpfwd},{n}"
		else:
			tcpfwd = n
	slirparg = f"{slirparg}/tcpfwd={tcpfwd}"
	if 'hostname' in slirp:
		hname = slirp['hostname']
		if not isinstance(hname, str):
			h.bail(f"'runner.slirp.hostname' must be str (not {type(hname)})")
		slirparg = f"{slirparg}/hostname={hname}"
slirpcmd += [ slirparg ]
run(slirpcmd)

## End of common-code. The remainder of the code is QEMU-specific.

# Our "disk" instance is really a copy-on-write layer on a global (and
# read-only) disk image. If it already exists, we're running in a configuration
# where the disk is persistent. Otherwise it only exists for the lifetime of
# the container (which is the uptime of the VM).
cowpath = f"{state}/disk.qcow2"
if not os.path.isfile(cowpath):
	run(f"qemu-img create -f qcow2 -F raw -b /qemu_caboodle_img/disk {cowpath}".split())

# Run the VM
cmd = [ "qemu-system-x86_64",
	"-drive", f"file={cowpath}",
	"-m", "4096", "-smp", "4", "-enable-kvm",
	"-kernel", "/qemu_caboodle_img/vmlinuz",
	"-initrd", "/qemu_caboodle_img/initrd.img",
	"-virtfs", f"local,path={hostfs_dir},security_model=passthrough,mount_tag=hcphostfs",
	"-nic", "vde,sock=/vdeswitch,mac=52:54:98:76:54:32,model=e1000",
	"-append" ]
if 'DISPLAY' in os.environ:
	cmd += [ "root=/dev/sda1", "-serial", "stdio" ]
	# Catch the common case, so it's easier to fix
	if os.environ['DISPLAY'] == ':0' and not os.path.exists('/tmp/.X11-unix/X0'):
		h.bail('Missing "socat" on the host for the X11 socket?')
	if os.path.isfile('/root/Xauthority'):
		# We expect $XAUTHKEY to contain the X11 magic cookie, and for
		# $XAUTHORITY to point to a source xauth file that we should
		# supplement.
		if 'XAUTHKEY' not in os.environ:
			h.bail('XAUTHKEY not defined')
		hname = socket.gethostname()
		shutil.copy('/root/Xauthority', '/root/.Xauthority')
		run(['xauth', 'add', f"{hname}/unix:0", '.', os.environ['XAUTHKEY']])
else:
	cmd += [ "root=/dev/sda1 console=ttyS0", "-nographic" ]
if mounts:
	if not isinstance(mounts, dict):
		h.bail(f"mounts must be a dict (not {type(mounts)})")
	for tag in mounts:
		m = mounts[tag]
		if isinstance(m, str):
			m = { 'path': m }
		if not isinstance(m, dict):
			h.bail(f"mounts[{dest}] must be str or dict (not {type(m)})")
		options = None
		if 'host_options' in m:
			options = m['host_options']
			if not isinstance(options, str):
				h.bail(f"mounts[{dest}] 'host_options' must be str (not {type(options)})")
		if 'host_path' in m:
			path = m['host_path']
		elif 'path' in m:
			path = m['path']
		else:
			h.bail(f"mounts[{dest}] missing the '[host_]path' attribute")
		if not isinstance(path, str):
			h.bail(f"mounts[{dest}] 'path' must be str (not {type(path)})")
		virtfsval = f"local,path={path},security_model=passthrough,mount_tag={tag}"
		if options:
			virtfsval = f"{virtfsval},{options}"
		cmd += [ "-virtfs", virtfsval ]
run(cmd)
