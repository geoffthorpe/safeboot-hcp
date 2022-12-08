#!/usr/bin/python3
# vim: set expandtab shiftwidth=4 softtabstop=4:

import os
import sys
import json
import subprocess
import time

sys.path.insert(1, '/hcp/common')
from hcp_common import bail, log, \
    hcp_config_extract, hcp_config_scope_get, hcp_config_scope_set, \
    hcp_config_scope_shrink

def mylog(s):
    if 'VERBOSE' in os.environ:
        log(s)

services = hcp_config_extract('services', or_default = True, default = [])
if not isinstance(services, list):
    bail(f"'services' field should be a list (not a {type(services)})")

launch_default = hcp_config_extract('default', or_default = True,
                    default = [ 'setup', 'start' ])
if not isinstance(launch_default, list):
    bail(f"'default' should be a list (not a {type(launch_default)})")
for i in launch_default:
    if not isinstance(i, str):
        bail(f"'default' should contain only str entries (not {type(i)})")

args_for = hcp_config_extract('args_for', or_default = True, default = '')
if not isinstance(args_for, str):
    bail(f"'args_for' should be a str (not a {type(args_for)})")

# Each child entry can optionally have an 'env' section to cause it to be
# launched with modified environment. 'env' can have 3 optional sections;
# 'pathadd', 'set', and 'unset'.
baseenv = os.environ.copy()
def childenv_init(child):
    global baseenv
    e = child['env']
    newenv = baseenv.copy()
    if 'set' in e:
        es = e['set']
        for k in es:
            newenv[k] = es[k]
    if 'pathadd' in e:
        ep = e['pathadd']
        for k in ep:
            if k in newenv and len(newenv[k]) > 0:
                newenv[k] = f"{newenv[k]}:{ep[k]}"
            else:
                newenv[k] = ep[k]
    if 'unset' in e:
        eu = e['unset']
        for k in es:
            newenv.pop[k]
    child['newenv'] = newenv

# Iterate through the 'services' array in the JSON, extracting and checking the
# corresponding fields and details. We build up two 'children_*' arrays
# consisting of curated content (so that, once done, we can use them without
# checking everything);
# * 'children_setup' is for services having 'setup' sections.
# * 'children_start' is for services having 'exec' attributes.
# Some items may be in both.
children_setup = []
children_start = []
children_all = []
for i in services:
    child = { 'name': i }
    mylog(f"HCP launcher: processing service {i}")
    # Switch our config scope into the child item so that we pull out the
    # attributes without having to meddle with paths - we switch back at the
    # end.
    config_backup = hcp_config_scope_get()
    hcp_config_scope_shrink(f".{i}")
    # If there's no 'exec', then we don't care about 'until', 'tag', 'uid',
    # 'gid', or 'args'.
    child['exec'] = hcp_config_extract('exec', or_default = True)
    if child['exec']:
        # 'exec' can be a string or a list of strings, normalize to latter.
        if isinstance(child['exec'], str):
            child['exec'] = [ child['exec'] ]
        elif not isinstance(child['exec'], list):
            bail(f"'{i}:exec' should be a str or list of str (not a {type(child['exec'])})")
        for e in child['exec']:
            if not isinstance(e, str):
                bail(f"'{i}:exec' can only contain str (not {type(e)})")
        child['until'] = hcp_config_extract('until', or_default = True)
        if child['until']:
            if not isinstance(child['until'], str):
                bail(f"'{i}:until' should be a str (not a {type(child['until'])})")
        child['tag'] = hcp_config_extract('tag', or_default = True)
        if child['tag']:
            if not isinstance(child['tag'], str):
                bail(f"'{i}:tag' should be a str (not a {type(child['tag'])})")
        uid = hcp_config_extract('uid', or_default = True)
        gid = hcp_config_extract('gid', or_default = True)
        if uid:
            if not isinstance(uid, str):
                bail(f"'{i}:uid' must be a str (not a {type(uid)})")
            if gid:
                if not isinstance(gid, str):
                    bail(f"'{i}:gid' must be a str (not a {type(gid)})")
        child['uid'] = uid
        child['gid'] = gid
        args = []
        if uid:
            args += [ 'runuser', '-w', 'HCP_CONFIG_FILE,HCP_CONFIG_SCOPE' ]
            if gid:
                args += [ '-g', gid ]
            args += [ '-u', uid ]
            args += [ '--' ]
        args += child['exec']
        child['exec'] = args
        xtra = hcp_config_extract('args', or_default = True)
        if xtra:
            if not isinstance(xtra, list):
                bail(f"'{i}:args' must be a list (not a {type(xtra)})")
            for check in xtra:
                if not isinstance(check, str):
                    bail(f"'{i}:args' must only contain strings")
        child['args'] = xtra
        nowait = hcp_config_extract('nowait', or_default = True)
        if nowait:
            child['nowait'] = True
        else:
            child['nowait'] = False
    child['setup'] = hcp_config_extract('setup', or_default = True)
    if child['setup']:
        # 'setup' can be a single dict or an array of dicts. We convert the
        # simple case to a single-entry array so that things are normalized.
        if isinstance(child['setup'], dict):
            setup = [ child['setup'] ]
        else:
            setup = child['setup']
            if not isinstance(setup, list):
                bail(f"'{i}:setup' must be a dict or list (not a {type(setup)})")
        for s in setup:
            if not isinstance(s, dict):
                bail(f"'{i}:setup[]' entries must be dicts (not {type(s)})")
            if 'exec' in s:
                setupbin = s['exec']
                if not isinstance(setupbin, str):
                    bail(f"'{i}:setup[]:exec' must be str (not {type(setupbin)})")
            else:
                s['exec'] = None
            if 'touchfile' not in s:
                bail(f"'{i}:setup[]:touchfile' must be provided")
            touchfile = s['touchfile']
            if not isinstance(touchfile, str):
                bail(f"'{i}:setup[]:touchfile' must be str (not {type(touchfile)})")
            if 'tag' in s:
                tag = s['tag']
                if not isinstance(tag, str):
                    bail(f"'{i}:setup[]:tag' must be str (not {type(tag)})")
            else:
                s['tag'] = None
        child['setup'] = setup
    # If we have 'env', it matters for both setup and/or exec
    child['env'] = hcp_config_extract('env', or_default = True)
    if child['env']:
        if not isinstance(child['env'], dict):
            bail(f"'{i}:env' must be a dict (not a {type(child['env'])}")
        for s in child['env']:
            if s not in [ 'pathadd', 'set', 'unset' ]:
                bail(f"'{i}:env' supports pathadd/set/unset (not '{s}')")
            v = child['env'][s]
            if not isinstance(v, dict):
                bail(f"'{i}:env:{v}' must be a dict (not a {type(v)})")
            for e in v:
                if not isinstance(e, str):
                    bail(f"'{i}:env:{v}', '{e}' must be a str (not a {type(e)})")
                ev = v[e]
                if not isinstance(ev, str):
                    bail(f"'{i}:env:{v}:{e}' must be a str (not a {type(ev)})")
        childenv_init(child)
    # Child curated, now where does it go, and does it fit there?
    if child['setup']:
        children_setup += [ child ]
    if child['exec']:
        children_start += [ child ]
    children_all += [ child ]
    # And don't forget to revert back to our config!
    hcp_config_scope_set(config_backup)

# bail() will call sys.exit() directly, whereas mybail() throws our custom
# exception. If we haven't yet started any processes to clean up, we use the
# former and needn't worry about state. If we have started processes, then we
# rely on there being an exception handler upstairs that will go through the
# process-cleanup loop before truly bailing out with the error.
class LauncherLocalException(Exception):
	pass
mybailready = False
mybailtext = None
def mybail(s):
    global mybailready
    global mybailtext
    if not mybailready:
        bail(s)
    mybailtext = s
    raise LauncherLocalException()

# We need to be save/restore child-specific environment settings, before and
# after calling subprocess.{run,Popen}(). Note, we can't simply copy os.environ
# and set it later - that will divorce os.environ from the actual environment.
# So we have to save and set individual key-value pairs, which on the contrary
# causes the actual environment to be updated in real-time.
def setenviron(e):
    # Set what needs to be set
    for k in e:
        os.environ[k] = e[k]
    # Unset what should disappear
    x = [ k for k in os.environ if k not in e ]
    for k in x:
        os.environ.pop(k)

def pre_subprocess(child):
    if 'newenv' in child:
        child['backupenv'] = os.environ.copy()
        setenviron(child['newenv'])
def post_subprocess(child):
    if 'newenv' in child:
        setenviron(child['backupenv'])

# The children_* arrays are global variables (so functions that use them must
# predeclare them as 'global', thanks python). Here, we add 'started' as
# another global, which accumulates (the 'popen' handles of) all subprocesses
# that we kicked off (and haven't yet reaped).
started = []

def run_custom(actions):
    log(f"HCP launcher: running {actions}")
    p = subprocess.run(actions)
    log(f"HCP launcher: exit code {p.returncode}")
    sys.exit(p.returncode)

def run_setup(tag = None):
    global children_setup
    for i in children_setup:
        n = i['name']
        setup = i['setup']
        for s in setup:
            if tag and tag != s['tag']:
                continue
            touchfile = s['touchfile']
            if os.path.isfile(touchfile):
                log(f"HCP launcher: '{n}:{touchfile}' already setup")
            else:
                if not s['exec']:
                    mybail(f"HCP launcher: '{n}:{touchfile}' has no setup function")
                log(f"HCP launcher: '{n}:{touchfile}' running setup: {s['exec']}")
                # Run the setup routine
                pre_subprocess(i)
                p = subprocess.run([s['exec']])
                post_subprocess(i)
                if p.returncode != 0:
                    mybail(f"HCP launcher: '{n}:{touchfile}' setup failed, code: {p.returncode}")
                if not os.path.isfile(touchfile):
                    mybail(f"HCP launcher: '{n}:{touchfile}' setup didn't create touchfile")

def run_start(tag = None):
    global started
    global children_start
    skipped = []
    local_started = []
    while len(children_start) > 0:
        i = children_start.pop()
        n = i['name']
        t = i['tag']
        _until = i['until']
        if tag and tag != t:
            skipped += [ i ]
            continue
        cmdargs = i['exec']
        if i['args']:
            cmdargs += i['args']
        log(f"HCP launcher: '{n}' starting: {cmdargs}")
        # Check any setup requirements
        setup = i['setup']
        if setup:
            for s in setup:
                touchfile = s['touchfile']
                if not os.path.isfile(touchfile):
                    mybail(f"HCP launcher: '{n}:{touchfile}' not setup")
        pre_subprocess(i)
        p = subprocess.Popen(cmdargs)
        post_subprocess(i)
        i['popen'] = p
        # If we need to poll for its 'until' touchfile to show up, add it to
        # local_started.
        if _until:
            local_started += [ i ]
        else:
            started += [ i ]
    children_start += skipped
    # Wait for any 'until' touchfiles to show up (and/or fail if those services
    # exit before getting that far).
    while True:
        x = []
        while len(local_started) > 0:
            i = local_started.pop()
            n = i['name']
            p = i['popen']
            touchfile = i['until']
            result = p.poll()
            if result and result != 0:
                mybail(f"HCP launcher: '{n}' failed")
            if os.path.isfile(touchfile):
                log(f"HCP launcher: '{n}:{touchfile}' complete")
                if not result:
                    started += [ i ]
                break
            if result == 0:
                mybail(f"HCP launcher: '{n}' didn't produce '{touchfile}'")
            x += [ i ]
        if len(x) == 0:
            break
        local_started = x
        time.sleep(0.5)

# What to do depends on the arguments we get. This script is often the
# 'entrypoint' of a container image, though it can be invoked directly (and is,
# in the 'caboodle' use-case). If we get cmd-line arguments, they could be for
# this script or for passing along to one of the services we start.
#
# We proceed as follows. We consume arguments for this script until we
# encounter one that is not recognized, or 'custom' which is necessarily the
# last such argument.
#
# This script recognizes;
#     setup start setup-* start-* custom
#
# If the last argument was 'custom' then the remaining arguments are assumed to
# be an arbitrary command-line to be started in the container.
#
# Otherwise, if the first unrecognized argument begins with a "-" character, we
# assume that the current argument (and all that follow it) are intended for
# one of the services. The ".args_for' property identifies which service that
# is. Each service (that isn't setup-only) has an 'exec' property and
# optionally an 'args' property.  By default, the two are concatenated into the
# command-line that gets executed. However if arguments are passed along to
# that service from our caller, they are used _instead_ of the 'args' property.
# This means the dividing line between the 'exec' and 'args' depends on what
# arguments you want _replaced_ if the user/caller passes in their own
# arguments. Note, if you want arguments passed to the ".args_for'-identified
# service that don't begin with "-", use "--" as the first argument - as a
# special case, we will consume that argument (not pass it along) but consider
# that all subsequent arguments should be passed even if the first one doesn't
# begin with "-".
#
# Otherwise (ie. when the first unrecognized argument doesn't begin with a "-"
# character), we behave as though the previous argument was 'custom'.

if len(sys.argv) < 2:
    actions = launch_default
else:
    actions = sys.argv.copy()
    actions.pop(0)

log(f"HCP launcher: processing options: {actions}")
tostart = []
while len(actions) > 0:
    action = actions.pop(0)
    log(f"HCP launcher: option: {action}")
    new_tostart = None
    if action == 'setup' or action.startswith('setup-'):
        if action.startswith('setup-'):
            new_tostart = ( 'setup-', action.replace('setup-', '') )
        else:
            new_tostart = ( 'setup' )
    elif action == 'start' or action.startswith('start-'):
        if action.startswith('start-'):
            new_tostart = ( 'start-', action.replace('start-', '') )
        else:
            new_tostart = ( 'start' )
    elif action == 'custom':
        new_tostart = ( 'custom', actions )
        actions = []
    elif action.startswith('-'):
        # There must be an 'args_for' service nominated to have its 'args' set.
        if not args_for or args_for not in services:
            bail(f"given arguments, but there's no 'args_for' service")
        if action != '--':
            # The current action was popped but needs to be inserted back
            actions.insert(0, action)
        # If there have been no start/setup/custom things before now, then
        # assume that what the user wants, rather than nothing at all, is the
        # default. To do this, we have to prepend the entire 'launch_default'
        # array, and then we loop back to process it all.
        if len(tostart) == 0:
            # In this case, even the '--' needs to be inserted back in
            if action == '--':
                actions.insert(0, action)
            mylog(f"HCP launcher: inserting 'launch_default' args: {launch_default}")
            actions = launch_default + actions
        else:
            args_transferred = False
            for c in children_all:
                if c['name'] == args_for:
                    mylog(f"HCP launcher: '{args_for}' service gets args: {actions}")
                    c['args'] = actions
                    actions = []
                    args_transferred = True
                    break
            if not args_transferred:
                bail(f"given arguments, but the service is missing: {args_for}")
    else:
        # Treat the current action and all remaining as a 'custom'.
        actions.insert(0, action)
        mylog(f"HCP launcher: custom gets args: {actions}")
        new_tostart = ( 'custom', actions )
        actions = []
    if new_tostart:
        mylog(f"HCP launcher: tostart += {new_tostart}")
        tostart += [ new_tostart ]

# From this point on, functions below us may call mybail() to throw an
# exception, with the intention that we escape out to the phase where we
# terminate anything we've started but that we haven't yet reaped.
res = None
ex = None
mybailready = True

try:

    for i in tostart:
        if i[0] == 'setup':
            run_setup()
        elif i[0] == 'setup-':
            run_setup(tag = i[1])
        elif i[0] == 'start':
            run_start()
        elif i[0] == 'start-':
            run_start(tag = i[1])
        elif i[0] == 'custom':
            run_custom(i[1])
            bail(f"HCP launcher: run_custom({actions}) shouldn't return")
        else:
            bail(f"HCP launcher: internal bug, bad 'tostart': {i}")

    # Everything that is to be done/started has been done/started. Now we wait for
    # things to exit. Note, if the only things left running all have 'nowait' set
    # True, we should exit. This is to cover things like 'fqdn_updater' - if
    # someone runs a setup stage, they expect the container to exit once it's done,
    # so if things like 'fqdn_updater' get started, we'll mark them 'nowait' so
    # that we don't pause indefinitely waiting for it to exit once the thing we
    # _were_ waiting on has already done so.
    mylog("HCP launcher: waiting for children to exit")
    while True:
        x = []
        num_waiting = 0
        while len(started) > 0:
            i = started.pop()
            n = i['name']
            p = i['popen']
            res = p.poll()
            if res == None:
                if not i['nowait']:
                    num_waiting += 1
                x += [ i ]
            else:
                break
        started = x
        if num_waiting == 0:
            break
        time.sleep(2)

except LauncherLocalException as e:

    log(f"Caught exception: {mybailtext}")
    ex = e

mybailready = False

# If there are any children remaining 'started', we're about to exit so
# encourage them to exit. In the cases where launcher is running as a
# container's entrypoint, this is arguably unnecessary and may even reduce
# reliability - eg. if a child process gets stuck and needs more than a
# SIGTERM. However, this is more elegant, and more importantly, it is essential
# when launcher is being invoked in a context that won't vanish when launcher
# exits! (Ie. launcher should clean up after itself, rather than leaving processes
# dangling.)
while len(started) > 0:
    i = started.pop()
    i['popen'].terminate()

# If something tried to mybail() and we caught it, do the bail() now
if ex:
    bail(mybailtext)

# If one of the services exited with error, bail() for that too
if res:
    if res == 0:
        log(f"HCP launcher: child {n} exited without error")
    else:
        bail(f"HCP launcher: child {n} failed: {res}")

mylog("HCP launcher: done")