#!/usr/bin/python3

import os
import subprocess

if 'DCOMPOSE' not in os.environ:
	os.environ['DCOMPOSE'] = 'docker-compose'

# wrapper.sh sets DCOMPOSE to the start of the command, which may consist of
# arguments, so we split based on ' '. This can be fixed when wrapper.sh itself
# is written in python. Until then, commands and arguments can't contain
# spaces, and never use more than one space between arguments.
dc = os.environ['DCOMPOSE'].split(' ')
verbose = 0

def log(v, s):
	if v <= verbose:
		print(f"service_test: {s}")

if 'VERBOSE' in os.environ:
	verbose = int(os.environ['VERBOSE'])
if verbose <= 0:
	log(0, "running quietly (set VERBOSE>0 for more)")
else:
	log(0, f"running with verbose={verbose}")

retries = 60
if 'RETRIES' in os.environ:
	retries = int(os.environ['RETRIES'])
	log(1, f"using retries={retries}")
else:
	log(1, f"defaulting to retries={retries}")
rargs = [ '-R', f"{retries}" ]

def dc_cmd(s, cont, cmd, args, isBinary = False,
			captureStdout = False,
			_input = None):
	log(0, s)
	allargs = dc.copy()
	if cmd == 'up':
		allargs += [ 'up', '-d' ]
		if cont:
			raise Exception("'up' takes containers as args only")
		if captureStdout:
			raise Exception("'up' command doesn't allow captureStdout")
	elif cmd == 'exec':
		allargs += [ 'exec', '-T']
	elif cmd == 'run':
		allargs += [ 'run', '--rm' ]
	else:
		allargs += [ cmd ]
	if cont:
		allargs += [ cont ]
	allargs += args
	log(1, f"running allargs={allargs}")
	mytext = not isBinary
	mystdout = None
	if captureStdout or verbose < 2:
		mystdout = subprocess.PIPE
	mystderr = None
	if verbose < 2:
		mystderr = subprocess.PIPE
	myinput = _input
	log(2, f"also, mytext={mytext}, myinput={myinput}")
	log(2, f"mystdout={mystdout}, mystderr={mystderr}")
	c = subprocess.run(allargs, text = mytext, input = myinput,
			stdout = mystdout, stderr = mystderr)
	if c.returncode != 0:
		log(0, f"FAILURE: exit code {c.returncode}")
		log(1, f"joined: {' '.join(allargs)}")
		raise Exception(f"'{cmd}' failed with exit code {c.returncode}")
	return c

dc_cmd("initializing enrollsvc state",
	'emgmt', 'run', [ 'start-presetup', 'setup-global' ])

dc_cmd("starting enrollsvc containers",
	None, 'up', [ 'emgmt', 'emgmt_pol', 'erepl' ])

dc_cmd("waiting for replication service to come up",
	'erepl', 'exec', [ '/hcp/enrollsvc/repl_healthcheck.sh' ] + rargs)

dc_cmd("initializing attestsvc state",
	'arepl', 'run', [ 'start-presetup', 'setup-global' ])

dc_cmd("starting attestsvc containers",
	None, 'up', [ 'arepl', 'ahcp' ])

dc_cmd("waiting for emgmt service to come up",
	'emgmt', 'exec', [ '/hcp/common/webapi.sh', 'healthcheck' ] + rargs)

dc_cmd("create aclient TPM",
	'orchestrator', 'run', '-- -c aclient'.split())

dc_cmd("starting aclient TPM",
	None, 'up', [ 'aclient_tpm' ])

dc_cmd("wait for aclient TPM to come up",
	'aclient_tpm', 'exec', [ '/hcp/swtpmsvc/healthcheck.sh' ] + rargs)

dc_cmd("run attestation client, expecting failure (unenrolled)",
	'aclient', 'run', [ '-w' ])

dc_cmd("enroll aclient TPM",
	'orchestrator', 'run', '-- -e aclient'.split())

dc_cmd("run attestation client, expecting eventual success (enrolled)",
	'aclient', 'run', rargs)

dc_cmd("create and enroll KDC TPMs",
	'orchestrator', 'run', '-- -c -e kdc_primary kdc_secondary'.split())

dc_cmd("starting KDC TPMs and policy engines",
	None, 'up', [ 'kdc_primary_tpm', 'kdc_secondary_tpm',
			'kdc_primary_pol', 'kdc_secondary_pol' ])

dc_cmd("wait for kdc_primary TPM to come up",
	'kdc_primary_tpm', 'exec', [ '/hcp/swtpmsvc/healthcheck.sh' ] + rargs)

dc_cmd("start kdc_primary", None, 'up', [ 'kdc_primary' ])

dc_cmd("wait for kdc_primary to come up",
	'kdc_primary', 'exec', [ '/hcp/common/webapi.sh', 'healthcheck' ] + rargs)

dc_cmd("wait for kdc_secondary TPM to come up",
	'kdc_secondary_tpm', 'exec', [ '/hcp/swtpmsvc/healthcheck.sh' ] + rargs)

dc_cmd("start kdc_secondary", None, 'up', [ 'kdc_secondary' ])

dc_cmd("wait for kdc_secondary to come up",
	'kdc_secondary', 'exec', [ '/hcp/common/webapi.sh', 'healthcheck' ] + rargs)

dc_cmd("create and enroll 'sherver' TPM",
	'orchestrator', 'run', '-- -c -e sherver'.split())

dc_cmd("start sherver TPM",
	None, 'up', [ 'sherver_tpm' ])

dc_cmd("wait for sherver TPM to come up",
	'sherver_tpm', 'exec', [ '/hcp/swtpmsvc/healthcheck.sh' ] + rargs)

dc_cmd("start sherver",
	None, 'up', [ 'sherver' ])

dc_cmd("wait for sherver to come up",
	'sherver', 'exec', [ '/hcp/sshsvc/healthcheck.sh' ] + rargs)

dc_cmd("create and enroll 'caboodle_networked' TPM",
	'orchestrator', 'run', '-- -c -e caboodlenet'.split())

dc_cmd("start TPM for client machine (caboodle_networked)",
	None, 'up', [ 'caboodle_networked_tpm' ])

dc_cmd("wait for client TPM to come up",
	'caboodle_networked_tpm', 'exec', [ '/hcp/swtpmsvc/healthcheck.sh' ] + rargs)

dc_cmd("start client machine (caboodle_networked)",
	None, 'up', [ 'caboodle_networked' ])

dc_cmd("waiting for the client machine to be up",
	'caboodle_networked', 'exec',
	[ '/hcp/caboodle/networked_healthcheck.sh' ] + rargs)

x = dc_cmd("obtaining the sshd server's randomly-generated public key",
	'sherver', 'exec',
	[ 'bash', '-c', 'ssh-keyscan sherver.hcphacking.xyz' ],
	captureStdout = True)

cmdstr = 'mkdir -p /root/.ssh && ' + \
	'chmod 600 /root/.ssh && ' + \
	'cat - > /root/.ssh/known_hosts'
dc_cmd("inject sshd pubkey into client's 'known_hosts'",
	'caboodle_networked', 'exec',
	[ 'bash', '-c', cmdstr ],
	_input = x.stdout)

cmdstr = 'kinit -C ' + \
	'FILE:/etc/ssl/hostcerts/hostcert-pkinit-user-user2-key.pem user2 ' + \
	'ssh -l user2 sherver.hcphacking.xyz ' + \
	'echo hello'
x = dc_cmd("Use HCP cred to get TGT, then GSSAPI to ssh from client to sherver",
	'caboodle_networked', 'exec',
	[ 'bash', '-c', '-l', cmdstr ],
	captureStdout = True)
if x.stdout.strip() != 'hello':
	log(0, f"FAILURE: output not 'hello': {x.stdout}")
	raise Exception("output mismatch from ssh session")

log(0, "success")
