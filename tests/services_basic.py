#!/usr/bin/python3

import os
import subprocess

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

dc_cmd("starting all services",
	None, 'up',
	[
		'emgmt', 'erepl', 'arepl', 'ahcp', 'emgmt_pol',
		'kdc_primary', 'kdc_primary_pol', 'kdc_primary_tpm',
		'kdc_secondary', 'kdc_secondary_pol', 'kdc_secondary_tpm',
		'sherver', 'sherver_tpm',
		'caboodle_networked', 'caboodle_networked_tpm',
		'aclient_tpm'
	])

dc_cmd("waiting for emgmt to come up",
	'emgmt', 'exec',
	[ '/hcp/enrollsvc/emgmt_healthcheck.sh' ] + rargs)

dc_cmd("creating and enrolling TPMs for the KDCs",
	'orchestrator', 'run',
	[ '-c', '-e', 'kdc_primary', 'kdc_secondary' ])

dc_cmd("waiting for kdc_primary to come up",
	'kdc_primary', 'exec',
	[ '/hcp/kdcsvc/healthcheck.sh' ] + rargs)

dc_cmd("creating and enrolling TPMs for everything else",
	'orchestrator', 'run', [ '-c', '-e' ])

dc_cmd("waiting for aclient's TPM to be up",
	'aclient_tpm', 'exec',
	[ '/hcp/swtpmsvc/healthcheck.sh' ] + rargs)

dc_cmd("running attestation client",
	'aclient', 'run', rargs)

dc_cmd("waiting for the sshd service to be up",
	'sherver', 'exec',
	[ '/hcp/sshsvc/healthcheck.sh' ] + rargs)

dc_cmd("waiting for the client (caboodle_networked) machine to be up",
	'caboodle_networked', 'exec',
	[ '/hcp/caboodle/networked_healthcheck.sh' ] + rargs)

x = dc_cmd("obtaining the sshd server's randomly-generated public key",
	'sherver', 'exec',
	[ 'bash', '-c', 'ssh-keyscan sherver.hcphacking.xyz' ],
	captureStdout = True)

cmdstr = 'mkdir -p /root/.ssh && ' + \
	'chmod 600 /root/.ssh && ' + \
	'cat - > /root/.ssh/known_hosts'
dc_cmd("loading that public key into client's 'known_hosts'",
	'caboodle_networked', 'exec',
	[ 'bash', '-c', cmdstr ],
	_input = x.stdout)

cmdstr = 'kinit -C ' + \
	'FILE:/etc/ssl/hostcerts/hostcert-pkinit-user-user2-key.pem user2 ' + \
	'ssh -l user2 sherver.hcphacking.xyz ' + \
	'echo hello'
x = dc_cmd("full ssh (+GSSAPI) test from client to sshd service",
	'caboodle_networked', 'exec',
	[ 'bash', '-c', '-l', cmdstr ],
	captureStdout = True)
if x.stdout.strip() != 'hello':
	log(0, f"FAILURE: output not 'hello': {x.stdout}")
	raise Exception("output mismatch from ssh session")

log(0, "success")
