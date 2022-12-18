#!/usr/bin/python3

# We use this wrapper to handle processes that might exit without us wanting
# the parent (typically the 'launcher.py' supervisor) to tear everything down
# as a result. Eg. if a secondary KDC comes up faster than a primary and so the
# iprop replication client fails to connect, we want it to retry.

import sys
import subprocess
import time

sys.path.insert(1, '/hcp/common')
from hcp_common import log

log(f"Inside restarter.py")

# We assume the command-line to be run is obtained by popping 'restarter.py'
# and any of its arguments off the head of the argv array.
sys.argv.pop(0)

# TODO: add arguments to support "escape velocity", e.g. two numbers
# controlling <how> many retries, if they occur within <how> long a time
# period, will cause us to deliberately fail. (Useful for dev/test, to catch
# problems that don't self-resolve. Probably less useful for prod.)
retry = 120
if sys.argv[0] == '-t':
	retry = int(sys.argv[1])
	sys.argv.pop(0)
	sys.argv.pop(0)

log(f"- retry period: {retry} seconds")

while True:
	log(f"restarter: starting: {sys.argv}")
	p = subprocess.run(sys.argv)
	log(f"restarter: process exit details: {p}")
	time.sleep(retry)
