#!/usr/bin/python3

import os
import sys
import json
import subprocess
import glob

# This needs to be kept consistent with qemu/runner.py

# Paths in /hostfs (in the container and UML instance)
hostfs_dir = '/hostfs'
hostfs_config = f"{hostfs_dir}/config.json"
hostfs_shutdown = "/myshutdown"

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

# Mount any "volumes" (docker-compose-speak) that were intended for us.
if 'mounts' in config:
	mounts = config['mounts']
	for tag in mounts:
		m = mounts[tag]
		if isinstance(m, str):
			m = { 'path': m }
		# See note about 'msize' in src/apps/qemu_rootfs.Dockerfile,
		# the other source of 'mount' commands inside the VM.
		if 'guest_options' not in m:
			m['guest_options'] = 'msize=10485760'
		args = [ 'mount', '-t', '9p', '-o', m['guest_options'] ]
		if 'guest_path' in m:
			dest = m['guest_path']
		elif 'path' in m:
			dest = m['path']
		else:
			dest = f"/{tag}"
		subprocess.run([ "mkdir", "-p", dest ])
		args += [ tag, dest ]
		subprocess.run(args)

args = config['argv']
# Run the desired command
if len(args) == 0 or args[0] == '--':
	args = [ '/hcp/common/launcher.py' ] + args
subprocess.run(args)

# Kill the UML kernel (last one out shuts the lights)
subprocess.run([hostfs_shutdown])
