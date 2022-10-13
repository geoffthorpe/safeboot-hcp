#!/usr/bin/python3

import sys
import os
import json
import subprocess
import tempfile

sys.path.insert(1, '/hcp/common')
to_trace = 'HCP_NO_TRACE' not in os.environ
if to_trace:
	from hcp_tracefile import tracefile
	tfile = tracefile(f"kdcsvc_kadmin")
	sys.stderr = tfile
else:
	tfile = sys.stderr
import hcp_common
log = hcp_common.log
bail = hcp_common.bail

# Usage:
# do_kadmin.py <cmd> <principals_list> <realm> <options>

if len(sys.argv) != 5:
	bail(f"Wrong number of arguments: {len(sys.argv)}")

cmd = sys.argv[1]
principals_json = sys.argv[2]
realm = sys.argv[3]
clientjson = sys.argv[4]
prefix = f"do_kadmin {cmd}"
def mylog(s):
	log(f"{prefix} {s}")
mylog("\n" +
	f" - principals_json={principals_json}\n" +
	f" - realm={realm}\n" +
	f" - clientjson={clientjson}")

if len(clientjson) == 0:
	clientjson = "{}"

# Don't error-check this, let the exceptions fly if there's anything wrong.
clientdata = json.loads(clientjson)
mylog(f"clientdata={clientdata}")
if not isinstance(clientdata, dict):
	bail(f"clientjson is of type {type(clientdata)}, not 'dict'")
verbose = 'verbose' in clientdata and clientdata['verbose']
principals_list = json.loads(principals_json)
mylog(f"principals_list={principals_list}")
principals_args = [ f"{x}{realm}" for x in principals_list ]
mylog(f"principals_args={principals_args}")

args = [ 'kadmin',
	f"--config-file={os.environ['HCP_KDC_STATE']}/etc/kdc.conf",
	'-l',
	cmd ]

if len(realm) > 0:
	realm = f"@{realm}"

def run_subprocess(cmd_args, base64wrap = None):
	if base64wrap:
		with tempfile.TemporaryDirectory() as td:
			tf = f"{td}/kt"
			all_args = args + [ base64wrap, tf ] + cmd_args
			mylog(f"running: {all_args}")
			c = subprocess.run(all_args,
				stdout = subprocess.PIPE, stderr = tfile,
				text = True)
			if c.returncode != 0:
				mylog(f"FAIL, exitcode={c.returncode}")
				sys.exit(500)
			b64args = ['base64', '--wrap=0', tf]
			mylog(f"running: {b64args}")
			c = subprocess.run(b64args,
				stdout = subprocess.PIPE, stderr = tfile,
				text = True)
	else:
		all_args = args + cmd_args
		mylog(f"running: {all_args}")
		c = subprocess.run(all_args,
				stdout = subprocess.PIPE, stderr = tfile,
				text = True)
	if c.returncode != 0:
		mylog(f"FAIL, exitcode={c.returncode}")
		sys.exit(500)
	res = {
		'cmd': cmd,
		'realm': realm,
		# Not 'principals', as that may be what we want to call the
		# output (eg. for "get"), so "requested" instead.
		'requested': principals_list,
		# Either this remains in raw form all the way to the user, or
		# the handler pop()s it and inserts something curated.
		'stdout': c.stdout
	}
	return res

# Add args to "kadmin -l", run it, and process the output
if cmd == "add":
	# TODO: support user profile for options
	add_args = [ '--use-defaults', '--random-key' ] + principals_args
	print(json.dumps(run_subprocess(add_args)))

elif cmd == "add_ns":
	# TODO: support user profile for options
	add_ns_args = [
		'--key-rotation-epoch=-1d',
		'--key-rotation-period=5m',
		'--max-ticket-life=1d',
		'--max-renewable-life=5d',
		'--attributes='
	] + principals_args
	print(json.dumps(run_subprocess(add_ns_args)))

elif cmd == "get":
	get_args = [ '--long' ] + principals_args
	# If no principals provided, we need to put a "*" on the cmd-line
	if len(principals_args) == 0:
		get_args += [ '*' ]
	res = run_subprocess(get_args)
	myout = res.pop('stdout')
	lines = myout.split('\n')
	if verbose:
		princs = {}
		current_fields = {}
	else:
		princs = []
	current_princ = ""
	lines += [ "" ] # This ensures the last output entry is flushed
	for i in lines:
		if len(i) == 0:
			# Assume this is the blank line between princs. Note
			# that an empty listing will hit this case once.
			if len(current_princ) == 0:
				continue
			# Flush the entry we've been parsing
			if current_princ in princs:
				mylog(f"FAIL, princ occurs twice?!: {current_princ}")
				sys.exit(500)
			mylog(f"inserting {current_princ}")
			if verbose:
				princs[current_princ] = current_fields
				current_fields = {}
			else:
				princs += [ current_princ ]
			current_princ = ""
			continue
		# Otherwise the line should be "<attribute>:<value>"
		# GOTCHA: <value> may contain ":", so set 'maxsplit=1'
		# GOTCHA: <attribute> may have indenting whitespace
		parts = i.split(":", 1)
		if len(parts) != 2:
			mylog(f"FAIL, non-empty line doesn't split\n{i}")
		a = parts[0].strip()
		v = parts[1]
		if len(current_princ) == 0:
			# The first attribute must be the "Principal"
			if a != "Principal":
				mylog(f"FAIL, first entry is not 'Principal': {a}")
				sys.exit(500)
			current_princ = v
		elif verbose:
			if a in current_fields:
				mylog(f"FAIL, attribute occurs twice?!: {a}")
				sys.exit(500)
			current_fields[a] = v
	res['principals'] = princs
	print(json.dumps(res))

elif cmd == 'del' or cmd == 'del_ns':
	del_args = principals_args
	print(json.dumps(run_subprocess(del_args)))

elif cmd == 'ext_keytab':
	# TODO: support user profile for options
	kt_args = principals_args
	print(json.dumps(run_subprocess(kt_args, base64wrap = '-k')))

else:
	mylog(f"Error, cmd={cmd} unrecognized")
	sys.exit(500)

log(f"{prefix} JSON output produced, exiting with code 201")
sys.exit(200)
