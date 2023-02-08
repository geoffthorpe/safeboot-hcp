#!/usr/bin/python3

# We use this sshd-wrapper in order to filter out the surplus logging on stderr
# caused by healthchecks. The healthcheck routine uses "ssh-keygen localhost",
# which probes the sshd to see what works and what doesn't and this generates
# junk into the logs. Fortunately these are distinguishable due to the localhost
# IP address, so we suppress those and let everything else through.

import sys
import subprocess

sys.path.insert(1, '/hcp/common')
from hcp_common import log

log(f"Inside run_sshd.py")

# We assume that our arguments are a fully-formed 'sshd <args>' command line.
sys.argv.pop(0)

p = subprocess.Popen(sys.argv, stderr = subprocess.PIPE, text = True)

while True:
	nextline = p.stderr.readline()
	if not nextline:
		break
	if nextline.find('127.0.0.1 port') == -1:
		print(nextline.rstrip(), file = sys.stderr)
		sys.stderr.flush()
