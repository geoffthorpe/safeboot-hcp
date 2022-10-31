import os
import sys
import time
from datetime import datetime, timezone, timedelta
import glob
import json
import re
import subprocess

sys.path.insert(1, '/hcp/common')
from hcp_common import log, bail, datetime2hint, exit2http

sys.path.insert(1, '/hcp/enrollsvc')
import db_common

log("reenroller: starting")

# We follow a series of steps in order to produce a list of enrollments that
# should be reenrolled.

# 1. 'fpath' is a wildcard pattern for use by 'glob', which does not support
# regular expressions, producing 'matches1', a superset of what we want.
fpath = f"{db_common.fpath_mask('')}/hint-reenroll-*"
log(f"reenroller: fpath={fpath}")
matches1 = glob.glob(fpath)

# 2. 'hintmatcher' is the regex to filter out surplus files, producing
# 'matches2'.
hintmatcher = re.compile('hint-reenroll-[0-9]*\.')
matches2 = [m for m in matches1 if not hintmatcher.search(m)]

# 3. convert each array entry (a path string) into a struct with the fields
# we'll need: 'matches3'
matches3 = [
	{
		'dirname': os.path.dirname(foo),
		'basename': os.path.basename(foo),
		'ekpubhash': open(f"{os.path.dirname(foo)}/ekpubhash",
					'r').read().strip('\n'),
		'hint': os.path.basename(foo).replace(
				'hint-reenroll-', '')
	} for foo in matches2 ]

# 4. put our list in 'basename' order - giving us the enrollments with the
# earliest reenrollment hints first. Then we're done, so call it 'matches'.
matches = matches3
matches.sort(key = lambda x : x['basename'])

hintnow = datetime2hint(datetime.now(timezone.utc))
s = f"now={hintnow}, matches={[foo['ekpubhash'][0:16] for foo in matches]}"
log(f"reenroller: loop-start: {s}")

for entry in matches:
	hint = entry['hint']
	ekpubhash = entry['ekpubhash']
	shorthash = ekpubhash[0:16]
	s = f"ekpubhash={shorthash}, hint={hint}"

	if hintnow < hint:
		log(f"reenroller: stopping on {s}")
		break
	log(f"reenroller: reenrolling {s}")

	clientdata = {
		'ekpubhash': ekpubhash
	}
	clientjson = json.dumps(clientdata)
	# It might seem weird to be running a python program using subprocess,
	# let me explain. The web API deliberately runs flask handlers as a
	# different non-root user from the actual operations that manipulate
	# the database (and issuer credentials). The web API handlers sanitize
	# each request and then requests the real operations through a
	# pinholed, environment-cleansing sudo call (to a bash script that
	# demuxes on the other side).
	#
	# So by design, that bash script is launched (by sudo) for each
	# individual operation, so the operations it calls are also launched in
	# a fresh interpreter to process the requested operation and then exit.
	# This has some security and reliability value: configuration is always
	# fresh, log-rotation is a no-brainer, garbage collection too, abort()
	# becomes a legitimate/safe/conservative way to deal with errors, etc).
	# In fact, when the process exits and the sudo call returns to the web
	# API handler, the stdout from the operation provides the return data
	# (JSON) and the exit code from the process provides the http status
	# code! (Relative to the http2exit/exit2http stuff defined in
	# common/hcp.sh and common/hcp_common.py. That's why we're checking for
	# '201' below, rather than the conventional posix '0'.)
	#
	# So _that's_ why the python operation is launched as a process, rather
	# than as a library call. (BTW, the bash demuxer running behind sudo
	# isn't the only other thing that launches db_add.py - self_enroll.sh
	# does it too, if enabled. The thing is, they're both in bash, so
	# nobody finds anything odd about them launching subprocesses.) :-)
	c = subprocess.run([ 'python3', '/hcp/enrollsvc/db_add.py',
			'reenroll', clientjson],
		stdout = subprocess.PIPE,
		stderr = subprocess.PIPE)
	httpcode = exit2http(c.returncode)
	if httpcode != 201:
		log(f"FAILURE: 'reenroll' of '{shorthash}';")
		log(f" - exitcode: {c.returncode}")
		log(f" - stdout: {c.stdout}")
		log(f" - stderr: {c.stderr}")
		bail("reenroller")

log("reenroller: loop-end")
