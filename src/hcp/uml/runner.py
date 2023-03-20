#!/usr/bin/python3

# Usage: runner.py <workload> [args...]

# This script runs inside the 'uml_runner' container and takes care of running
# the UML instance. It should not be confused with code running inside the UML
# instance (init.py and myshutdown).
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
#         "init_env": { ... }
#       }
#     - 'HCP_CONFIG_FILE' points to the usecase corresponding to <workload>,
#     - 'argv' contains any remaining cmd-line "args...",
#     - 'init_env' is passed along from the 'runner' JSON input, if it exists.
#   - we hardlink /hostfs/myshutdown, the executable that the 'init.py' script
#     within the UML instance can invoke to stop the kernel.
#   - we start vde_switch in the container (at /vdeswitch)
#   - we start slirpvde in the container (plugged into /vdeswitch)
# The UML kernel is started with args;
#   - 'eth0=vde,/vdeswitch' (so it's plugged it into the vde_switch)
#   - 'init=/hcp/uml/init.py'

import os
import sys
import json
import shutil
import subprocess

sys.path.insert(1, '/hcp/common')
import hcp_common as h

# Process cmd-line
if len(sys.argv) < 2:
	raise Exception('runner.py requires at least one argument')
print(f"DONG")
sys.argv.pop(0)
workload = sys.argv.pop(0)
print(f"workload={workload}", file=sys.stderr)

# Paths in the container
rootfs = "/rootfs.ext4"
fqdn_bus = "/fqdn-bus"
uml_shutdown = "/hcp/uml/myshutdown"

# Paths in /hostfs (in the container and UML instance)
hostfs_dir = '/hostfs'
hostfs_config = f"{hostfs_dir}/config.json"
hostfs_rootfs = f"{hostfs_dir}/rootfs.ext4"
hostfs_usecase = f"{hostfs_dir}/usecase"
hostfs_shutdown = f"{hostfs_dir}/myshutdown"

# Prepare the JSON-encoded config
config = {
	'HCP_CONFIG_FILE': f"{hostfs_usecase}/{workload}.json",
	'argv': sys.argv
}
init_env = h.hcp_config_extract('runner.init_env', or_default = True)
if init_env:
	config['init_env'] = init_env

# Copy the readonly ext4 to something the UML instance can manipulate (and
# whose changes will disappear after exit)
shutil.copyfile(rootfs, hostfs_rootfs)

# Dump config (HCP_CONFIG_FILE and [args...]) as JSON
with open(hostfs_config, 'w') as fp:
	json.dump(config, fp)

# Link the myshutdown script
os.link(uml_shutdown, hostfs_shutdown)

# Start up a VDE switch and plug a slirpvde instance into it (for DHCP, DNS,
# and router)
subprocess.run("vde_switch -d -s /vdeswitch -M /vdeswitch_mgmt".split())
# TODO: need to make this configurable;
# - "--host" argument to stipulate what network addresses to use (to avoid
#   conflicting with other networks the host cares about).
# - "-L/-U" for opening access to the VM (like "--publish" for docker)
subprocess.run("slirpvde --daemon --dhcp /vdeswitch".split())

# Run the UML instance
# TODO: need to filter out (somehow) the 'reboot' output from the UML instance.
# Or, use a different interface for IO.
cmd = f"/linux ubd0={hostfs_rootfs} root=/dev/ubda rw hostfs={hostfs_dir} " + \
	f"eth0=vde,/vdeswitch quiet mem=2G init=/hcp/uml/init.py"
subprocess.run(cmd.split())
