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

try:
	verbosity = int(os.environ['VERBOSE'])
except:
	verbosity = 1

# We are currently a healthcheck script, so no need for '--healthcheck'.
parser = argparse.ArgumentParser()
#parser.add_argument("--healthcheck", action = "store_true",
#		help = "check that swtpm is running ok")
parser.add_argument("-R", "--retries", type = int, default = 0,
		help = "for healthcheck, max # of retries")
parser.add_argument("-P", "--pause", type = int, default = 1,
		help = "for healthcheck, pause (seconds) between retries")
parser.add_argument("-v", "--verbose", default = 0, action = "count",
		help = "increase output verbosity")
parser.add_argument("-V", "--less-verbose", default = 0, action = "count",
		help = "decrease output verbosity")
args = parser.parse_args()
# For now, always true
args.healthcheck = True
verbosity = verbosity + args.verbose - args.less_verbose
h.current_loglevel = verbosity
os.environ['VERBOSE'] = f"{verbosity}"

if args.healthcheck:
	h.hlog(1, f"Running: do_kadmin.py realm_healthcheck")
	while True:
		c = subprocess.run(
			[
				'/hcp/kdcsvc/do_kadmin.py',
				'realm_healthcheck',
				'[]',
				'{}'
			],
			capture_output = True)
		# do_kadmin.py is designed as a web-serving helper, and returns
		# http status codes "compressed" into the range of exit codes
		# via hcp_common::http2exit(). An exit code of 20 corresponds to an http
		# status code of 200, which is success.
		if c.returncode == 20:
			c.returncode = 0
			break
		h.hlog(1, f"Failed with code: {c.returncode}")
		h.hlog(1, f"(http={h.exit2http(c.returncode)})")
		h.hlog(2, f"Error output:\n{c.stderr}")
		if args.retries == 0:
			h.hlog(0, "Failure, giving up")
			break
		args.retries = args.retries - 1
		if args.pause > 0:
			h.hlog(2, f"Pausing for {args.pause} seconds")
			time.sleep(args.pause)
	sys.exit(c.returncode)

h.bail("unreachable code?!")
