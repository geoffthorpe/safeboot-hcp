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

sys.path.insert(1, '/hcp/common')
import hcp_common as h

# Process cmd-line
if len(sys.argv) < 2:
	raise Exception('runner.py requires at least one argument')
sys.argv.pop(0)
workload = sys.argv.pop(0)
print(f"qemu runner launching workload: {workload}", file=sys.stderr)

# Paths in /hostfs (in the container and the VM)
hostfs_dir = '/hostfs'
hostfs_config = f"{hostfs_dir}/config.json"

# Prepare the JSON-encoded config
config = {
	'HCP_CONFIG_FILE': f"/usecase/{workload}.json",
	'argv': sys.argv
}
init_env = h.hcp_config_extract('runner.init_env', or_default = True)
if init_env:
	config['init_env'] = init_env

# Dump config (HCP_CONFIG_FILE and [args...]) as JSON
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
run("slirpvde --daemon --dhcp /vdeswitch".split())

# Create a copy-on-write layer on the (read-only) disk image
run("qemu-img create -b /qemu_caboodle_img/disk -f qcow2 /tmp.qcow2".split())

# Run the VM
cmd = [ "qemu-system-x86_64",
	"-drive", "file=/tmp.qcow2",
	"-m", "4096",
	"-kernel", "/qemu_caboodle_img/vmlinuz",
	"-initrd", "/qemu_caboodle_img/initrd.img",
	"-virtfs", f"local,path={hostfs_dir},security_model=mapped-xattr,mount_tag=hcphostfs",
	"-nic", "vde,sock=/vdeswitch,mac=52:54:98:76:54:32,model=e1000",
	"-append", "root=/dev/sda1 console=ttyS0" ]
if 'XAUTHORITY' in os.environ and 'DISPLAY' in os.environ:
	cmd += [ "-serial", "stdio" ]
else:
	cmd += [ "-nographic" ]
run(cmd)
