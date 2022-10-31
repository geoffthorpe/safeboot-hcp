#!/usr/bin/python3

import sys
import os
import subprocess
import time

sys.path.insert(1, '/hcp/common')
from hcp_common import log, bail, current_tracefile, hcp_config_extract, \
	hcp_config_scope_set, hcp_config_scope_get, hcp_config_scope_shrink

_period = hcp_config_extract('.attester.period', must_exist = True)
try:
	period = int(_period)
except ValueError as e:
	log(f"ERROR: .attester.period ({_period}) must be a number")
	log(f"{e}")
	sys.exit(1)
cmd_args = [ '/hcp/tools/run_client.sh' ]

log(f"Starting attester")
log(f" - period={period}")
log(f" - cmd_args={cmd_args}")

while True:
	res = 0
	try:
		log("Running command")
		c = subprocess.run(cmd_args, stderr = current_tracefile,
				text = True)
		res = c.returncode
	except Exception as e:
		log(f"Warning, exception: {e}")
	log(f"Command exited with code={res}")
	time.sleep(period)
