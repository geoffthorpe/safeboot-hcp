#!/usr/bin/python3

import sys
import os
import subprocess
import time

sys.path.insert(1, '/hcp/common')
to_trace = 'HCP_NO_TRACE' not in os.environ
if to_trace:
	from hcp_tracefile import tracefile
	tfile = tracefile("attester")
	sys.stderr = tfile
from hcp_common import log, bail

_period = os.environ['HCP_ATTESTER_PERIOD']
try:
	period = int(_period)
except ValueError as e:
	log(f"ERROR: HCP_ATTESTER_PERIOD ({_period}) must be a number")
	log(f"{e}")
	sys.exit(1)
cmd_args = [ '/hcp/tools/run_client.sh' ]
touchfile = None
if 'HCP_ATTESTER_TOUCHFILE' in os.environ:
	touchfile = os.environ['HCP_ATTESTER_TOUCHFILE']

log(f"Starting attester")
log(f" - period={period}")
log(f" - cmd_args={cmd_args}")

while True:
	res = 0
	try:
		log("Running command")
		if to_trace:
			c = subprocess.run(cmd_args, stderr = tfile, text = True)
		else:
			c = subprocess.run(cmd_args, text = True)
		res = c.returncode
	except Exception as e:
		log(f"Warning, exception: {e}")
	log(f"Command exited with code={res}")
	if res == 0:
		if touchfile:
			# This is the closest thing we seem to have to the
			# "touch" command. It needs to handle initialization
			# races but does not need to handle a racing delete.
			with open(touchfile, 'a'):
				os.utime(touchfile, None)
	time.sleep(period)
