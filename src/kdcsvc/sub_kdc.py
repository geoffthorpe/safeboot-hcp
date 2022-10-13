#!/usr/bin/python3

import sys
import os
import subprocess
import time

env_mode = os.environ['HCP_KDC_MODE']

sys.path.insert(1, '/hcp/common')
to_trace = 'HCP_NO_TRACE' not in os.environ
if to_trace:
	from hcp_tracefile import tracefile
	tfile = tracefile(f"kdcsvc_{env_mode}_kdc")
	sys.stderr = tfile
from hcp_common import log, bail

env_state = os.environ['HCP_KDC_STATE']
env_etc = f"{env_state}/etc"

cmd_args = [
	'kdc',
	f"--config-file={env_etc}/kdc.conf"
	]

log(f"Starting {env_mode} kdc")
log(f" - cmd_args={cmd_args}")

while True:
	res = 0
	try:
		if to_trace:
			c = subprocess.run(cmd_args, stderr = tfile, text = True)
		else:
			c = subprocess.run(cmd_args, text = True)
		res = c.returncode
		log(f"Warning, 'kdc' exited with code={res}")
	except Exception as e:
		log(f"Warning, exception: {e}")
	log(f" - sleeping for 30 seconds before retrying")
	time.sleep(30)
	log(f" - retrying")
