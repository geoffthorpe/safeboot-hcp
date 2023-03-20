#!/usr/bin/python3

import os
import sys
import json
import subprocess

# This needs to be kept consistent with uml/runner.py

# Paths in /hostfs (in the container and UML instance)
hostfs_dir = '/hostfs'
hostfs_config = f"{hostfs_dir}/config.json"
hostfs_shutdown = f"{hostfs_dir}/myshutdown"

# 'shell'ish python to set up the network and filesystem, using what's provided
# by our partner, runner.py, which is outside (and launching) this VM.
shp = [
	'mount -t proc proc /proc/',
	'mount -t sysfs sys /sys/',
	'mount -t tmpfs tmpfs /tmp/',
	'dhclient eth0',
	f'mkdir -p {hostfs_dir}',
	f'mount -t hostfs none {hostfs_dir}'
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

# Make any requested "mounts". For UML we are not really mounting anything. The
# runner put hardlinks from the hostfs tree to the intended directories and we
# create hardlinks from the intended paths back to those links in hostfs.
if 'mounts' in config:
	mounts = config['mounts']
	for tag in mounts:
		m = mounts[tag]
		if isinstance(m, str):
			m = { 'path': m }
		if not isinstance(m, dict):
			h.bail(f"mounts[{m}] should be str or dict (not {type(m)})")
		# TODO: as per uml/runner.py, we should support the different
		# attribute types than just "path".
		path = m['path']
		if not path.startswith('/'):
			h.bail(f"mounts[{m}] ({path}) must be an absolute path")
		if not os.path.isdir(f"{hostfs_dir}/mounts{path}"):
			h.bail(f"mounts[{m}] ({hostfs_dir}/mounts{path}) doesn't exist")
		os.symlink(f"{hostfs_dir}/mounts{path}", path)

args = config['argv']
# Run the desired command
if len(args) == 0 or args[0] == '--':
	args = [ '/hcp/common/launcher.py' ] + args
print(f"Made it this far!! Next, args: {args}", file=sys.stderr)
subprocess.run(args)

# Kill the UML kernel (last one out shuts the lights)
subprocess.run([hostfs_shutdown])
