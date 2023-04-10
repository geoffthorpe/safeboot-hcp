#!/usr/bin/python3

### Initial code is common between qemu/runner.py and uml/runner.py

# Usage: runner.py <workload> [args...]

# This script runs inside the 'uml_runner' container and takes care of running
# the UML instance. It should not be confused with code running inside the UML
# instance.
# Expectations: we are started via launcher, with a JSON config whose 'runner'
# section may contain an 'init_env' section. We also expect the following
# mounts;
#   - /hostfs/usecase
#   - /hostfs/fqdn-bus
# Before starting the UML instance, we;
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
import shutil

sys.path.insert(1, '/hcp/common')
import hcp_common as h

# Process cmd-line
workload = None
if 'HCP_CONFIG_FILE' in os.environ:
	workload = os.environ['HCP_CONFIG_FILE']
sys.argv.pop(0)
if len(sys.argv) > 1:
	workload = sys.argv.pop(0)
print(f"uml runner launching workload: {workload}", file=sys.stderr)

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
ports = h.hcp_config_extract('runner.ports', or_default = True)
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
slirpcmd = "slirpvde --daemon --dhcp=10.0.2.15 --dns=10.0.2.3 /vdeswitch".split()
if ports:
	# TODO: it's not clear how to be certain of the address the VM will
	# get, other than it's the first (only) DHCP client and by default the
	# DHCP server (apparently) hands out addresses from 10.0.2.15 onwards.
	# <shrug>
	vdehost = '10.0.2.15'
	for p in ports:
		slirpcmd += [ '-L', f"{p}:{vdehost}:{p}" ]
run(slirpcmd)

## End of common-code. The remainder of the code is UML-specific.

if mounts:
	# Our method of passing /hcp, /usecase, /fqdn-bus [...] mounts into the
	# VM differs from QEMU. We only pass a single mount, the /hostfs mount
	# that is already in place to convey config to the VM. So we copy the
	# to-be-mounted directories into /hostfs, and inside the VM, the
	# uml_init.py script will symlink to them from their intended paths.
	# TODO: this isn't very good, obviously. It may be that UML can be made
	# to use virtfs too, in which case we could make it do what QEMU does.
	os.mkdir(f"{hostfs_dir}/mounts")
	for tag in mounts:
		v = mounts[tag]
		if isinstance(v, str):
			v = { 'path': v }
		if not isinstance(v, dict):
			h.bail(f"mounts[{m}] should be str or dict (not {type(v)})")
		# TODO: if we stick with this way of working, we should support the
		# different attribute types than just "path"
		path = v['path']
		if not path.startswith('/'):
			h.bail(f"mounts[{m}] ({path}) must be an absolute path")
		if not os.path.isdir(path):
			h.bail(f"mounts[{m}] ({path}) doesn't exist")
		os.makedirs(f"{hostfs_dir}/mounts{os.path.dirname(path)}",
				exist_ok = True)
		run(['cp', '-r', path,
			f"{hostfs_dir}/mounts{path}" ])

# TODO: get CoW working, it's silly to make a full copy
shutil.copy('/uml_caboodle.ext4', '/foo.ext4')

# Run the UML instance
# TODO: need to filter out (somehow) the 'reboot' output from the UML instance.
# Or, use a different interface for IO.
cmd = f"/linux ubd0=/foo.ext4 root=/dev/ubda rw hostfs={hostfs_dir} " + \
	f"eth0=vde,/vdeswitch mem=2G init=/uml_init.py"
	#f"eth0=vde,/vdeswitch quiet mem=2G init=/uml_init.py"
run(cmd.split())
