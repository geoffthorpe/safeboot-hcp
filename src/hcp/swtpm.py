#!/usr/bin/python3

import os
import sys
import subprocess
import argparse
import time
import shutil
import json

sys.path.insert(1, '/hcp/common')
import hcp_common as h

myworld = h.hcp_config_extract(".", must_exist = True)

def param(field, _type, required = False, default = None,
		obj = myworld, objpath = ''):
	if field in obj:
		v = obj[field]
		if not isinstance(v, _type):
			h.bail(f"'{objpath}.{field}' must be {_type}, not {type(v)}")
		return v
	if required:
		h.bail(f"'{objpath}.{field}' missing but required")
	return default

myinstance = param('id', str, required = True)
mydomain = param('default_domain', str, required = True)

myswtpm = param('swtpm', dict, required = True)

def swtpm_param(field, _type, required = True, default = None):
	return param(field, _type, required = required, default = default,
			obj = myswtpm, objpath = f".swtpm")

mystate = swtpm_param('state', str)
mysockdir = swtpm_param('sockdir', str)

mytpmsocket = f"{mysockdir}/tpm"
mytcti = f"swtpm:path={mytpmsocket}"

try:
	verbosity = int(os.environ['VERBOSE'])
except:
	verbosity = 1

parser = argparse.ArgumentParser()
parser.add_argument("--healthcheck", action = "store_true",
		help = "check that swtpm is running ok")
parser.add_argument("-R", "--retries", type = int, default = 0,
		help = "for healthcheck, max # of retries")
parser.add_argument("-P", "--pause", type = int, default = 1,
		help = "for healthcheck, pause (seconds) between retries")
parser.add_argument("-v", "--verbose", default = 0, action = "count",
		help = "increase output verbosity")
parser.add_argument("-V", "--less-verbose", default = 0, action = "count",
		help = "decrease output verbosity")
parser.add_argument("-T", "--tcti", default = mytcti,
		help = "TCTI (for tpm2-tss) string, path to TPM")
args = parser.parse_args()
verbosity = verbosity + args.verbose - args.less_verbose
h.current_loglevel = verbosity
os.environ['VERBOSE'] = f"{verbosity}"

os.environ['TPM2TOOLS_TCTI'] = args.tcti

if args.healthcheck:
	h.hlog(1, f"Running: tpm2_pcrread (TPM2TOOLS_TCTI={args.tcti})")
	while True:
		c = subprocess.run([ 'tpm2_pcrread' ], capture_output = True)
		if c.returncode == 0:
			break
		h.hlog(1, f"Failed with code: {c.returncode}")
		h.hlog(2, f"Error output:\n{c.stderr}")
		if args.retries == 0:
			h.hlog(0, "Failure, giving up")
			break
		args.retries = args.retries - 1
		if args.pause > 0:
			h.hlog(2, f"Pausing for {args.pause} seconds")
			time.sleep(args.pause)
	sys.exit(c.returncode)

h.hlog(2, f"Changing directory: {mystate}")
os.chdir(mystate)

swtpmcmd = [
	'swtpm', 'socket', '--tpm2',
	'--tpmstate', f"dir={mystate}/tpm",
	'--server', f"type=unixio,path={mytpmsocket}",
	'--ctrl', f"type=unixio,path={mytpmsocket}.ctrl",
	'--flags', 'startup-clear'
]
h.hlog(1, f"Starting swtpm: {swtpmcmd}")
# NB: swtpm generates a _lot_ of identical errors to stderr - mute it
if verbosity > 1:
	subprocess.run(swtpmcmd)
else:
	subprocess.run(swtpmcmd, stderr = subprocess.DEVNULL)
