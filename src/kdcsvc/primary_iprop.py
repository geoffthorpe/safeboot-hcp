#!/usr/bin/python3

import sys
import os
import subprocess
import time

sys.path.insert(1, '/hcp/common')
to_trace = 'HCP_NO_TRACE' not in os.environ
if to_trace:
	from hcp_tracefile import tracefile
	tfile = tracefile("kdcsvc_primary_iprop")
	sys.stderr = tfile
from hcp_common import log, bail

env_state = os.environ['HCP_KDC_STATE']
env_etc = f"{env_state}/etc"
env_host = os.environ['HCP_HOSTNAME']
env_domain = os.environ['HCP_FQDN_DEFAULT_DOMAIN']

cmd_args = [
	'ipropd-master',
	f"--config-file={env_etc}/kdc.conf",
	'--keytab=HDBGET:',
	f"--hostname={env_host}.{env_domain}",
	'--verbose'
	]

log(f"Starting ipropd-master")
log(f" - cmd_args={cmd_args}")

while True:
	res = 0
	try:
		if to_trace:
			c = subprocess.run(cmd_args, stderr = tfile, text = True)
		else:
			c = subprocess.run(cmd_args, text = True)
		res = c.returncode
		log(f"Warning, 'ipropd-master' exited with code={res}")
	except Exception as e:
		log(f"Warning, exception: {e}")
	log(f" - sleeping for 30 seconds before retrying")
	time.sleep(30)
	log(f" - retrying")
