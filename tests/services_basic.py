#!/usr/bin/python3
# vim: set expandtab shiftwidth=4 softtabstop=4:

# We don't want this script dependent on any (other) HCP code, as we want
# to be able to run it from the host-side. This is why we're not using the
# conventional log() function from hcp_common.py.

import os
import sys
import subprocess
import tempfile
import json

verbose = 0

def log(v, s):
    if v <= verbose:
        print(f"service_test: {s}")

def bail(s):
    log(0, f"FAILURE: {s}")
    raise Exception("something's wrong")

if 'VERBOSE' in os.environ:
    verbose = int(os.environ['VERBOSE'])
if verbose <= 0:
    log(0, "running quietly (set VERBOSE>0 for more)")
else:
    log(0, f"running with verbose={verbose}")

dc_cmd = [ 'docker-compose' ]
if 'DCOMPOSE' in os.environ:
    dc_cmd = os.environ['DCOMPOSE'].split()

start_fqdn = [ 'start-fqdn' ]
monolith_mode = False
if 'HCP_IN_MONOLITH' in os.environ:
    monolith_mode = True
    monolith_dir = tempfile.mkdtemp()
    os.chmod(monolith_dir, 0o755)
    monolith_children = {}
    start_fqdn = []

retries = 60
if 'RETRIES' in os.environ:
    retries = int(os.environ['RETRIES'])
    log(1, f"using retries={retries}")
else:
    log(1, f"defaulting to retries={retries}")
rargs = [ '-R', f"{retries}" ]

def do_subprocess(args, *, isBackground = False, isBinary = False,
                    captureStdout = False, _input = None, env = None):
    log(1, f"do_subprocess() starting")
    log(1, f"- args: {args}")
    log(2, f"- isBinary: {isBinary}")
    log(2, f"- captureStdout: {captureStdout}")
    log(3, f"- env: {env}")
    log(3, f"- input: {_input}")
    mytext = not isBinary
    mystdout = None
    if captureStdout or verbose < 2:
        mystdout = subprocess.PIPE
    mystderr = None
    if verbose < 2:
        mystderr = subprocess.PIPE
    if isBackground:
        if _input:
            bail("can't use input with backgrounded tasks")
        return subprocess.Popen(args, text = mytext,
                stdout = mystdout, stderr = mystderr, env = env)
    c = subprocess.run(args, text = mytext, input = _input,
            stdout = mystdout, stderr = mystderr, env = env)
    if c.returncode != 0:
        bail(f"exit code {c.returncode}")
    return c

# These do_*() routines are where we specialize between scenarios being run via
# docker-compose (from the host) or directly to launcher.py (from inside a
# 'monolith' container).

def pre_monolith(cname):
    newenv = os.environ.copy()
    newenv['HCP_IN_MONOLITH'] = "True"
    newenv['HCP_CONFIG_FILE'] = f"{monolith_dir}/{cname}.json"
    if 'HCP_CONFIG_SCOPE' in newenv:
        newenv.pop('HCP_CONFIG_SCOPE')
    try:
        with open(f"/usecase/{cname}.json", 'r') as fp:
            origjson = json.load(fp)
        if 'services' in origjson:
            services = origjson['services']
            services = [ s for s in services if s != 'fqdn_updater' ]
            origjson['services'] = services
        if 'default_targets' in origjson:
            targets = origjson['default_targets']
            targets = [ t for t in targets if t != 'start-fqdn' ]
            origjson['default_targets'] = targets
        if 'fqdn_updater' in origjson:
            p = origjson.pop('fqdn_updater')
            if 'hostnames' in p:
                hn = p['hostnames']
                if 'default_domain' in p:
                    dd = p['default_domain']
                    hn = [ f"{h}.{dd}" for h in hn ]
                with open('/hcp-my-fqdn', 'a') as fp:
                    for h in hn:
                        fp.write(f"{h}\n")
        with open(newenv['HCP_CONFIG_FILE'], 'w') as fp:
            json.dump(origjson, fp)
        os.chmod(newenv['HCP_CONFIG_FILE'], 0o644)
    except Exception as e:
        bail(f"JSON processing failed: {e}")
    return newenv

def do_foreground(cname, args, **kwargs):
    if not isinstance(cname, str):
        bail(f"'cname' ({cname}) must be a 'str'")
    if not isinstance(args, list):
        bail(f"'args' ({args}) must be a 'list'")
    if monolith_mode:
        newenv = pre_monolith(cname)
        return do_subprocess([ "/hcp/common/launcher.py" ] + args,
                                env = newenv, **kwargs)
    args = dc_cmd + [ 'run', '--rm', cname ] + args
    return do_subprocess(args, **kwargs)

def do_background(cnames, **kwargs):
    if isinstance(cnames, str):
        cnames = [ cnames ]
    elif not isinstance(cnames, list):
        bail(f"'cnames' ({cnames}) must be a 'str' or 'list'")
    if monolith_mode:
        for cname in cnames:
            newenv = pre_monolith(cname)
            ret = do_subprocess([ "/hcp/common/launcher.py" ],
                            isBackground = True, env = newenv, **kwargs)
            monolith_children[cname] = {
                'popen': ret,
                'name': cname
            }
    else:
        args = dc_cmd + [ 'up', '-d' ] + cnames
        do_subprocess(args, **kwargs)

def do_exec(cname, args, **kwargs):
    if not isinstance(cname, str):
        bail(f"'cname' ({cname}) must be a 'str'")
    if not isinstance(args, list):
        bail(f"'args' ({args}) must be a 'list'")
    if monolith_mode:
        newenv = pre_monolith(cname)
        return do_subprocess([ "/hcp/common/launcher.py", "custom" ] + args,
                                env = newenv, **kwargs)
    args = dc_cmd + [ 'exec', '-T', cname ] + args
    return do_subprocess(args, **kwargs)

log(0, "initializing enrollsvc state")
do_foreground('emgmt', start_fqdn + [ 'setup-global' ])

log(0, "starting enrollsvc containers")
do_background([ 'emgmt', 'emgmt_pol', 'erepl' ])

log(0, "waiting for replication service to come up")
do_exec('erepl', [ '/hcp/enrollsvc/repl_healthcheck.sh' ] + rargs)

log(0, "initializing attestsvc state")
do_foreground('arepl', [ 'start-fqdn', 'setup-global' ])

log(0, "starting attestsvc containers")
do_background([ 'arepl', 'ahcp' ])

log(0, "waiting for emgmt service to come up")
do_exec('emgmt', [ '/hcp/common/webapi.sh', 'healthcheck' ] + rargs)

log(0, "create aclient TPM")
do_foreground('orchestrator', '-- -c aclient'.split())

log(0, "starting aclient TPM")
do_background([ 'aclient_tpm' ])

log(0, "wait for aclient TPM to come up")
do_exec('aclient_tpm', [ '/hcp/swtpmsvc/healthcheck.sh' ] + rargs)

log(0, "run attestation client, expecting failure (unenrolled)")
do_foreground('aclient', [ '-w' ])

log(0, "enroll aclient TPM")
do_foreground('orchestrator', '-- -e aclient'.split())

log(0, "run attestation client, expecting eventual success (enrolled)")
do_foreground('aclient', rargs)

log(0, "create and enroll KDC TPMs")
do_foreground('orchestrator', '-- -c -e kdc_primary kdc_secondary'.split())

log(0, "starting KDC TPMs and policy engines")
do_background([ 'kdc_primary_tpm', 'kdc_secondary_tpm',
        'kdc_primary_pol', 'kdc_secondary_pol' ])

log(0, "wait for kdc_primary TPM to come up")
do_exec('kdc_primary_tpm', [ '/hcp/swtpmsvc/healthcheck.sh' ] + rargs)

log(0, "start kdc_primary")
do_background([ 'kdc_primary' ])

log(0, "wait for kdc_primary to come up")
do_exec('kdc_primary', [ '/hcp/common/webapi.sh', 'healthcheck' ] + rargs)

log(0, "wait for kdc_secondary TPM to come up")
do_exec('kdc_secondary_tpm', [ '/hcp/swtpmsvc/healthcheck.sh' ] + rargs)

log(0, "start kdc_secondary")
do_background([ 'kdc_secondary' ])

log(0, "wait for kdc_secondary to come up")
do_exec('kdc_secondary', [ '/hcp/common/webapi.sh', 'healthcheck' ] + rargs)

log(0, "create and enroll 'sherver' TPM")
do_foreground('orchestrator', '-- -c -e sherver'.split())

log(0, "start sherver TPM")
do_background([ 'sherver_tpm' ])

log(0, "wait for sherver TPM to come up")
do_exec('sherver_tpm', [ '/hcp/swtpmsvc/healthcheck.sh' ] + rargs)

log(0, "start sherver")
do_background([ 'sherver' ])

log(0, "wait for sherver to come up")
do_exec('sherver', [ '/hcp/sshsvc/healthcheck.sh' ] + rargs)

log(0, "create and enroll 'workstation1' TPM")
do_foreground('orchestrator', '-- -c -e workstation1'.split())

log(0, "start TPM for client machine (workstation1)")
do_background([ 'workstation1_tpm' ])

log(0, "wait for client TPM to come up")
do_exec('workstation1_tpm', [ '/hcp/swtpmsvc/healthcheck.sh' ] + rargs)

log(0, "start client machine (workstation1)")
do_background([ 'workstation1' ])

log(0, "waiting for the client machine to be up")
do_exec('workstation1', [ '/hcp/caboodle/networked_healthcheck.sh' ] + rargs)

log(0, "obtaining the sshd server's randomly-generated public key")
x = do_exec('sherver',
    [ 'bash', '-c', 'ssh-keyscan sherver.hcphacking.xyz' ],
    captureStdout = True)

log(0, "inject sshd pubkey into client's 'known_hosts'")
cmdstr = 'mkdir -p /root/.ssh && ' + \
    'chmod 600 /root/.ssh && ' + \
    'cat - > /root/.ssh/known_hosts'
do_exec('workstation1',
    [ 'bash', '-c', cmdstr ],
    _input = x.stdout)

log(0, "Use HCP cred to get TGT, then GSSAPI to ssh from client to sherver")
cmdstr = 'kinit -C ' + \
    'FILE:/home/luser/.hcp/pkinit/user-luser-key.pem luser ' + \
    'ssh -l luser sherver.hcphacking.xyz ' + \
    'echo hello'
x = do_exec('workstation1',
    [ 'bash', '-c', '-l', cmdstr ],
    captureStdout = True)
if x.stdout.strip() != 'hello':
    log(0, f"FAILURE: output not 'hello': {x.stdout}")
    raise Exception("output mismatch from ssh session")

log(0, "success")
