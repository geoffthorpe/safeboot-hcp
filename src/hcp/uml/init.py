#!/usr/bin/python3

import os
import sys
import json
import subprocess

# This needs to be kept consistent with runner.py

# Paths in /hostfs (in the container and UML instance)
hostfs_dir = '/hostfs'
hostfs_config = f"{hostfs_dir}/config.json"
hostfs_shutdown = f"{hostfs_dir}/myshutdown"

# 'shell'ish python to set up the network and filesystem, using what's provided
# by our partner, runner.py, which is outside (and launching) this VM.
shp = [
	'mount -t proc proc /proc/',
	'mount -t sysfs sys /sys/',
	'dhclient eth0',
	f'mkdir -p {hostfs_dir}',
	f'mount -t hostfs none {hostfs_dir}',
	f'ln -s {hostfs_dir}/usecase /usecase',
	f'ln -s {hostfs_dir}/fqdn-bus /fqdn-bus'
]
for i in shp:
	subprocess.run(['bash', '-c', i])

# Parse the config
with open(hostfs_config, 'r') as fp:
	config = json.load(fp)
os.environ['HCP_CONFIG_FILE'] = config['HCP_CONFIG_FILE']
if 'init_env' in config:
	# This is pulled from bits of launcher.py. This env handling should be
	# a library... As such, for now, I'm not doing any of the type checking
	# and fancy-pants stuff that launcher is doing.
	init_env = config['init_env']
	if 'unset' in init_env:
		for k in init_env['unset']:
			if k in os.environ:
				os.environ.pop(k)
	if 'set' in init_env:
		kv = init_env['set']
		for k in kv:
			os.environ[k] = kv[k]
	if 'pathadd' in init_env:
		kv = init_env['pathadd']
		for k in kv:
			if k in os.environ and len(os.environ[k]) > 0:
				os.environ[k] = f"{os.environ[k]}:{kv[k]}"
			else:
				os.environ[k] = kv[k]

args = config['argv']
# Run the desired command
if len(args) == 0 or args[0] == '--':
	args = [ '/hcp/common/launcher.py' ] + args
print(f"Made it this far!! Next, args: {args}", file=sys.stderr)
subprocess.run(args)

# Kill the UML kernel (last one out shuts the lights)
subprocess.run([hostfs_shutdown])
