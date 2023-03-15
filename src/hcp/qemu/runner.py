#!/usr/bin/python3

# Usage: runner.py <workload> [args...]

# This script runs inside the 'qemu_runner' container and takes care of running
# the QEMU instance. It should not be confused with code running inside the
# QEMU instance (init.py and myshutdown).
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
#         "init_env": { ... }
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

# Paths in /hostfs (in the container and the VM)
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
ports = h.hcp_config_extract('runner.ports', or_default = True)
# This one is interesting, because we're taking a prop from fqdn_updater,
# rather than runner. This avoids us having to tweak and relocate the 'usecase'
# JSON to inject the container networks into the fqdn_updater that will run
# inside the VM. We simply embed it in the config JSON here, and that
# fqdn_updater instance in the VM will look out for it.
publish_networks = h.hcp_config_extract('fqdn_updater.publish_networks',
					or_default = True)
if publish_networks:
	# TODO: we're taking the fqdn_updater's path, which is in the container,
	# and we're passing it to the fqdn_updater running in the VM, which will
	# use it as a path there too. Not a general solution.
	config['publish_networks'] = publish_networks

# Dump config (HCP_CONFIG_FILE, **argv, mounts) as JSON for the guest
with open(hostfs_config, 'w') as fp:
	json.dump(config, fp)

def run(cmd):
	print(f"{cmd}", file = sys.stderr)
	subprocess.run(cmd)

# Start up a VDE switch and plug a slirpvde instance into it (for DHCP, DNS,
# and router)
run("vde_switch -d -s /vdeswitch -M /vdeswitch_mgmt".split())
# TODO: need to make this configurable;
# - "--host" argument to stipulate what network addresses to use (to avoid
#   conflicting with other networks the host cares about).
# - "-L/-U" for opening access to the VM (like "--publish" for docker)
slirpcmd = "slirpvde --daemon --dhcp /vdeswitch".split()
if ports:
	# TODO: it's not clear how to be certain of the address the VM will
	# get, other than it's the first (only) DHCP client and by default the
	# DHCP server (apparently) hands out addresses from 10.0.2.15 onwards.
	# <shrug>
	vdehost = '10.0.2.15'
	for p in ports:
		slirpcmd += [ '-L', f"{p}:{vdehost}:{p}" ]
run(slirpcmd)

# Create a copy-on-write layer on the (read-only) disk image
run("qemu-img create -f qcow2 -F raw -b /qemu_caboodle_img/disk /tmp.qcow2".split())

# Run the VM
cmd = [ "qemu-system-x86_64",
	"-drive", "file=/tmp.qcow2",
	"-m", "4096", "-smp", "4",
	"-kernel", "/qemu_caboodle_img/vmlinuz",
	"-initrd", "/qemu_caboodle_img/initrd.img",
	"-virtfs", f"local,path={hostfs_dir},security_model=passthrough,mount_tag=hcphostfs",
	"-nic", "vde,sock=/vdeswitch,mac=52:54:98:76:54:32,model=e1000",
	"-append", "root=/dev/sda1 console=ttyS0" ]
if 'XAUTHORITY' in os.environ and 'DISPLAY' in os.environ:
	cmd += [ "-serial", "stdio" ]
else:
	cmd += [ "-nographic" ]
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
