#!/usr/bin/python3

import sys
import os
import json
import subprocess
import tempfile
import requests
from uuid import uuid4

sys.path.insert(1, '/hcp/common')
from hcp_common import log, bail, current_tracefile, \
		http2exit, exit2http, hcp_config_extract

sys.path.insert(1, '/hcp/xtra')

from HcpRecursiveUnion import union
import HcpJsonExpander

# Usage:
# do_kadmin.py <cmd> <principals_list> <clientprofile>

if len(sys.argv) != 4:
	bail(f"Wrong number of arguments: {len(sys.argv)}")

cmd = sys.argv[1]
principals_json = sys.argv[2]

clientjson = sys.argv[3]
if len(clientjson) == 0:
	clientjson = "{}"
prefix = f"do_kadmin {cmd}"
def mylog(s):
	log(f"{prefix} {s}")
mylog("\n" +
	f" - principals_json={principals_json}\n" +
	f" - clientjson={clientjson}")

defdomain = hcp_config_extract('.kdcsvc.namespace', must_exist = True)

# Load the server's config and extract the "preclient" and "postclient"
# profiles. Let exceptions do our error-checking.
serverprofile = hcp_config_extract('.kdcsvc.kadmin', must_exist = True)
serverprofile_pre = serverprofile.pop('preclient', {})
serverprofile_post = serverprofile.pop('postclient', {})

# Now merge with the client. Basically this is a non-shallow merge, in which
# the client's (requested) profile is overlaid on the server's "preclient"
# profile, and then the server's "postclient" profile is overlaid on top of
# that.
clientdata = json.loads(clientjson)
if not isinstance(clientdata, dict):
	bail(f"clientjson is of type {type(clientdata)}, not 'dict'")
mylog(f"clientdata={clientdata}")
resultprofile = union(union(serverprofile_pre, clientdata), serverprofile_post)
mylog(f"client-adjusted resultprofile={resultprofile}")

# Now we need to perform parameter-expansion. At the end, we have the KDC_JSON env-var set
# to the merged and expanded profile _for the requested command_. Note that this includes
# any "<common>" underlay and the merged environment attached as "__env".
origenv = resultprofile.pop('__env', {})
resultprofile = HcpJsonExpander.process_obj(origenv, resultprofile, '.',
					varskey = None, fileskey = None)

# So far, we've followed the enrollsvc example. Here add kdcsvc's own handling
# of <common> and the extracting of the commands-specific subsection.
commonprofile = resultprofile.pop('<common>', {})
commandprofile = resultprofile.pop(cmd, {})
resultprofile[cmd] = union(commonprofile, commandprofile)
resultprofile['__cmd'] = cmd
# And the final step follows enrollsvc.
resultprofile['__env'] = origenv
os.environ['KDC_JSON'] = json.dumps(resultprofile)
mylog(f"param-expanded resultprofle={resultprofile}")

# Extract the realm from the profile and inject the principals_list (which is
# the only parameter not passed outside the profile) _into_ the profile.
if 'realm' not in resultprofile[cmd]:
	mylog(f"'realm' not in the profile")
	sys.exit(http2exit(500))
realm = resultprofile[cmd]['realm']
principals_list = json.loads(principals_json)
resultprofile[cmd]['principals'] = principals_list
mylog(f"principals_list={principals_list}")

# The JSON profile is fully curated. Before acting on it, (a) check whether
# _we_ allow the command to be contemplated at all, and if so (b) send it to
# the policy checker to see if it is OK with this.
if 'allowed' in resultprofile:
	if cmd not in resultprofile['allowed']:
		mylog(f"command {cmd} is not in the profile's 'allowed' list")
		sys.exit(http2exit(403))
policy_url = hcp_config_extract('.kdcsvc.policy_url', or_default = True)
if policy_url and cmd != 'realm_healthcheck':
	uuid = uuid4().urn
	os.environ['HCP_REQUEST_UID'] = uuid
	form_data = {
		'request_uid': (None, uuid),
		'params': (None, json.dumps(resultprofile))
	}
	url = f"{policy_url}/run"
	mylog(f"sending policy request={form_data}")
	response = requests.post(url, files=form_data)
	mylog(f"policy response={response}")
	if response.status_code != 200:
		mylog(f"policy-checker refused operation: {response.status_code}")
		sys.exit(http2exit(403))

# Automatically suffix all the requested principals with the requested realm
realm_suffix = f"@{realm}"
realm_healthcheck = False
if cmd == 'realm_healthcheck':
	cmd = 'ext_keytab'
	realm_healthcheck = True
	principals_list = [ f"host/healthcheck.{defdomain}" ]
principals_args = [ f"{x}{realm_suffix}" for x in principals_list ]
mylog(f"principals_args={principals_args}")
# Verbosity is an option
verbose = 'verbose' in clientdata and clientdata['verbose']

kdcstate = hcp_config_extract('.kdcsvc.state', must_exist = True)
args = [ 'kadmin', f"--config-file={kdcstate}/etc/kdc.conf",
		'-l', cmd ]

def run_subprocess(cmd_args, base64wrap = None):
	if base64wrap:
		with tempfile.TemporaryDirectory() as td:
			tf = f"{td}/kt"
			all_args = args + [ base64wrap, tf ] + cmd_args
			mylog(f"running: {all_args}")
			c = subprocess.run(all_args,
				stdout = subprocess.PIPE,
				stderr = current_tracefile,
				text = True)
			if c.returncode != 0:
				mylog(f"FAIL, exitcode={c.returncode}")
				sys.exit(http2exit(500))
			b64args = ['base64', '--wrap=0', tf]
			mylog(f"running: {b64args}")
			c = subprocess.run(b64args,
				stdout = subprocess.PIPE,
				stderr = current_tracefile,
				text = True)
	else:
		all_args = args + cmd_args
		mylog(f"running: {all_args}")
		c = subprocess.run(all_args,
				stdout = subprocess.PIPE,
				stderr = current_tracefile,
				text = True)
	if c.returncode != 0:
		mylog(f"FAIL, exitcode={c.returncode}")
		sys.exit(http2exit(500))
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
				sys.exit(http2exit(500))
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
				sys.exit(http2exit(500))
			current_princ = v
		elif verbose:
			if a in current_fields:
				mylog(f"FAIL, attribute occurs twice?!: {a}")
				sys.exit(http2exit(500))
			current_fields[a] = v
	res['principals'] = princs
	print(json.dumps(res))

elif cmd == 'del' or cmd == 'del_ns':
	del_args = principals_args
	print(json.dumps(run_subprocess(del_args)))

elif cmd == 'ext_keytab':
	# TODO: support user profile for options
	kt_args = principals_args
	res = run_subprocess(kt_args, base64wrap = '-k')
	# Special case, 'cmd==realm_healthcheck' is rewritten to ext_keytab and we
	# finish that hook here.
	if realm_healthcheck:
		print("OK: healthcheck principal obtained")
	else:
		print(json.dumps(res))

else:
	mylog(f"Error, cmd={cmd} unrecognized")
	sys.exit(http2exit(500))

mylog(f"JSON output produced, exiting with code 200")
sys.exit(http2exit(200))
