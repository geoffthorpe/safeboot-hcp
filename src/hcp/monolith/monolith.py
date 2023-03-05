#!/usr/bin/python3

# vim: set expandtab shiftwidth=4 softtabstop=4:

# There are two main ideas behind the polymorphic 'caboodle' container image;
# 1. it has all the code for everything and can be used as the backing image
#    for running any instance/workload.
# 2. it can be used to host all the workloads in a single container, rather
#    than spread across multiple containers.
#
# This script is used for the second case. It provides a setup step for a
# container to run as a single-container, all-services-running-cotenant
# "monolith".
#
# The main job here is to create the directories for each service's persistent
# state. Usually, these would be mounted volumes, for which the directories in
# the container are created implicitly. Here though, the "persistence" is
# relative to workloads/instances getting started and stopped within the
# monolith container, but are not expected to persist across the monolith
# container being recycled, so we just create them as ordinary directories at
# container-startup.

import os
import sys
import pwd
import subprocess
import tempfile
import json
import shutil
import psutil
import glob
import signal

sys.path.insert(1, '/hcp/common')
from hcp_common import touch, bail, log, hlog, hcp_config_extract

monolith_dir = '/monolith'
monolith_runlogs = f"{monolith_dir}/__runlogs"

def logpath(cname, isBackground, ioname):
    hlog(1, f"logpath({cname},{isBackground},{ioname})")
    if isBackground:
        return f"{monolith_dir}/{cname}/{ioname}"
    return f"{monolith_runlogs}/{cname}.{ioname}"

def do_subprocess(cname, args, *, isBackground = False, isBinary = False,
                    captureStdout = False, _input = None, env = None,
                    logout = None, logerr = None, logjoined = None):
    hlog(1, f"do_subprocess() starting")
    hlog(1, f"- args: {args}")
    hlog(1, f"- isBackground: {isBackground}")
    hlog(2, f"- isBinary: {isBinary}")
    hlog(2, f"- captureStdout: {captureStdout}")
    hlog(3, f"- logout: {logout}")
    hlog(3, f"- logerr: {logerr}")
    hlog(3, f"- env: {env}")
    hlog(3, f"- input: {_input}")
    mytext = not isBinary
    mystdout = None
    if captureStdout:
        mystdout = subprocess.PIPE
    elif logout:
        stdoutpath = logpath(cname, isBackground, 'stdout')
        mystdout = open(stdoutpath, 'w')
        log(f"Directing stdout to {stdoutpath}")
    mystderr = None
    if logerr:
        if logout and logjoined:
            mystderr = mystdout
            log(f"Directing stderr to stdout")
        else:
            stderrpath = logpath(cname, isBackground, 'stderr')
            mystderr = open(stderrpath, 'w')
            log(f"Directing stderr to {stderrpath}")
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

def pre_monolith(cname):
    converted = f"{monolith_dir}/json.{cname}"
    newenv = os.environ.copy()
    newenv['HCP_IN_MONOLITH'] = "True"
    newenv['HCP_CONFIG_FILE'] = converted
    if 'HCP_CONFIG_SCOPE' in newenv:
        newenv.pop('HCP_CONFIG_SCOPE')
    try:
        with open(f"/usecase/{cname}.json", 'r') as fp:
            origjson = json.load(fp)
        # The reason we convert the JSON is to add the 'no_recolt' attribute.
        origjson['no_recolt'] = None
        with open(newenv['HCP_CONFIG_FILE'], 'w') as fp:
            json.dump(origjson, fp)
        os.chmod(converted, 0o644)
    except Exception as e:
        bail(f"JSON processing failed: {e}")
    return newenv

def do_foreground(cname, args, *, as_exec = False, **kwargs):
    if not isinstance(cname, str):
        bail(f"'cname' ({cname}) must be a 'str'")
    if not isinstance(args, list):
        bail(f"'args' ({args}) must be a 'list'")
    log(f"Foregrounding '{cname}'")
    mdir = f"{monolith_dir}/{cname}"
    hlog(2, f"Locking with mkdir({mdir})")
    # 'run_fg' must only proceed if "the container" doesn't exist yet, and must
    # block another instance from starting until the first one is done.
    # 'exec' can only work _while_ an instance is running.
    #
    # So we use mkdir/rmdir for mutual-exclusion on the former, and then we
    # create and delete an ephemeral touchfile inside that directory for
    # the latter.
    if as_exec:
        touchfile = f"{mdir}/exec.{os.getpid()}"
        with open(touchfile, 'w') as fp:
            fp.write("# never mind")
    else:
        os.mkdir(mdir)
    try:
        newenv = pre_monolith(cname)
        ret = do_subprocess(cname, [ "/hcp/common/launcher.py" ] + args,
                                env = newenv, **kwargs)
    finally:
        hlog(2, f"Unlocking with rmdir({mdir})")
        if as_exec:
            os.remove(touchfile)
        else:
            os.rmdir(mdir)
    return ret

def do_background(cname, args, **kwargs):
    if not isinstance(cname, str):
        bail(f"'cname' ({cname}) must be a 'str'")
    log(f"Backgrounding '{cname}'")
    mdir = f"{monolith_dir}/{cname}"
    hlog(2, f"Locking with mkdir({mdir})")
    os.mkdir(mdir)
    try:
        newenv = pre_monolith(cname)
        ret = do_subprocess(cname, [ "/hcp/common/launcher.py" ] + args,
                        isBackground = True, env = newenv, **kwargs)
    except e:
        hlog(2, f"Error, unlocking with rmtree({mdir})")
        shutil.rmtree(mdir)
        raise e
    with open(f"{mdir}/pid", 'w') as fp:
        fp.write(f"{ret.pid}")
    return ret

def do_exec(cname, args, **kwargs):
    if not isinstance(cname, str):
        bail(f"'cname' ({cname}) must be a 'str'")
    if not isinstance(args, list):
        bail(f"'args' ({args}) must be a 'list'")
    mdir = f"{monolith_dir}/{cname}"
    if not os.path.isdir(mdir):
        bail(f"can't 'exec' on an unstarted service")
    newenv = pre_monolith(cname)
    return do_subprocess(cname, [ "/hcp/common/launcher.py", "custom" ] + args,
                            env = newenv, **kwargs)

def is_created(cname):
    mdir = f"{monolith_dir}/{cname}"
    return os.path.isdir(mdir)

def get_status(cname):
    mpid = f"{monolith_dir}/{cname}/pid"
    if os.path.isfile(mpid):
        try:
            pid = int(open(mpid, 'r').read())
        except:
            bail(f"can't read 'pid' from '{mpid}'")
        try:
            proc = psutil.Process(pid)
        except psutil.NoSuchProcess:
            proc = None
        if proc:
            with proc.oneshot():
                return {
                    'pid': pid,
                    'name': proc.name(),
                    'status': proc.status()
                }
    return None

if __name__ == '__main__':

    # We try the argv array as we consume its entries. The first one is already
    # consumed.
    sys.argv = sys.argv[1:]

    # Utility function to slurp out any args that specify what to do about logging,
    # and return (remaining args, logstdout, logstderr).
    def logargs(args):
        logo = False
        loge = False
        logj = False
        while True:
            if len(args) == 0:
                break
            if not args[0].startswith('-l'):
                break
            if args[0] == '-l':
                logo = True
                loge = True
                logj = True
            elif args[0] == '-lout':
                logo = True
            elif args[0] == '-lerr':
                loge = True
            else:
                break
            args = args[1:]
        return args, logo, loge, logj
    
    config = hcp_config_extract('monolith', must_exist = True)
    log(f"config={config}")

    if len(sys.argv) == 0:
        bail("monolith.py expects arguments")
    cmd = sys.argv.pop(0)

    # The 'bootsrap' command gets run during global setup of the container. The
    # other commands get called by test cases or interactively, after the
    # container is ready.

    if cmd == 'bootstrap':

        log("Monolith setup")

        # We expect monolith to have a 'setup' sub-field, of list-type, containing
        # at least one entry, the last of which should be tagged as 'local' and
        # specify a touchfile! :-)
        if 'setup' not in config or not isinstance(config['setup'], list):
                bail("monolith config doesn't have a valid 'setup'")
        setup = config['setup']
        if len(config['setup']) < 1:
                bail("monolith::setup must have at least one element")
        setuplast = setup[-1]
        if 'tag' not in setuplast or setuplast['tag'] != 'local':
                bail(f"monolith::setup[-1] must be tagged 'local': {setuplast}")
        if 'touchfile' not in setuplast:
                bail(f"monolith::setup[-1]::touchfile doesn't exist: {setuplast}")
        touchfile = setuplast['touchfile']

        if os.path.isfile(touchfile):
                log(f"touchfile already configured, bypassing setup")
                sys.exit(0)

        if 'fakemounts' not in config:
                bail(f"monolith config doesn't have a valid 'fakemounts'")
        fmounts = config['fakemounts']

        for p in fmounts:
                log(f"fakemount: {p}")
                if not isinstance(p, str):
                        bail(f"fakemount[] must contain only 'str' (not {type(p)})")
                if os.path.isdir(p):
                        log("- already exists")
                else:
                        os.makedirs(p, mode = 0o755)
                        log("- created")

        # Finally, prepare the directory we use for statefulness
        os.makedirs(monolith_dir, mode = 0o755)
        # And for logs
        os.makedirs(monolith_runlogs, mode = 0o755)

        # That's the completion of bootstrapping
        touch(touchfile)

    elif cmd == 'run_fg':

        args, logout, logerr, logj = logargs(sys.argv)

        if len(args) == 0:
            bail("'monolith.py run_fg' requires at least one more argument")
        cname = args[0]
        args = args[1:]

        hlog(1, f"Monolith 'run_fg': {cname}")
        hlog(2, f"- args: {args}")

        if is_created(cname):
            bail(f"'{cname}' is already running")

        c = do_foreground(cname, args, logout = logout, logerr = logerr,
                            logjoined = logj)
        sys.exit(c.returncode)

    elif cmd == 'run_bg':

        args, logout, logerr, logj = logargs(sys.argv)

        if len(args) == 0:
            bail("'monolith.py run_bg' requires at least one more argument")
        cname = args[0]
        args = args[1:]

        hlog(1, f"Monolith 'run_bg': {cname}")
        hlog(2, f"- args: {args}")

        if is_created(cname):
            bail(f"'{cname}' is already running")

        c = do_background(cname, args, logout = logout, logerr = logerr,
                            logjoined = logj)
        sys.exit(c.returncode)

    elif cmd == 'start':

        args, logout, logerr, logj = logargs(sys.argv)

        if len(args) == 0:
            bail("'monolith.py start' requires at least one more argument")

        hlog(1, f"Monolith 'start': {args}")

        for cname in args:
            if is_created(cname):
                print(f"'{cname}' is already created, skipping")
                continue
            c = do_background(cname, [], logout = logout, logerr = logerr,
                                logjoined = logj)
            print(f"'{cname}' is started")

    elif cmd == 'exec':

        args = sys.argv

        if len(args) == 0:
            bail("'monolith.py exec' requires at least one more argument")
        cname = args[0]
        args = args[1:]

        hlog(1, f"Monolith 'exec': {cname}")
        hlog(2, f"- args: {args}")

        if not is_created(cname):
            bail(f"'{cname}' isn't running")

        c = do_foreground(cname, args, as_exec = True)
        sys.exit(c.returncode)

    elif cmd == 'status':

        args = sys.argv
        # If given no arguments (container names), scan
        if len(args) == 0:
            matches = glob.glob(f"{monolith_dir}/*/")
            for m in matches:
                if m.find('__runlogs') != -1:
                    continue
                args.append(os.path.basename(os.path.dirname(m)))

        for cname in args:
            if is_created(cname):
                s = get_status(cname)
                if not s:
                    print(f"'{cname}' created, but stopped")
                else:
                    print(f"'{cname}' created: {s}")
            else:
                print(f"'{cname}' isn't created")

    elif cmd == 'stop':
    
        args = sys.argv
    
        if len(args) == 0:
            bail("'monolith.py stop' requires at least one more argument")
    
        hlog(1, f"Monolith 'stop': {args}")
    
        for cname in args:
            if not is_created(cname):
                print(f"'{cname}' isn't created, skipping")
                continue
            s = get_status(cname)
            if not s:
                print(f"'{cname}' created, but busted")
            else:
                print(f"'{cname}' terminating (pid={s['pid']})")
                p = psutil.Process(s['pid'])
                p.send_signal(signal.SIGTERM)
                p.wait()
                print(f"'{cname}' terminated")
                os.remove(f"{monolith_dir}/{cname}/pid")
    
    elif cmd == 'rm':
    
        args = sys.argv
    
        if len(args) == 0:
            bail("'monolith.py stop' requires at least one more argument")
    
        hlog(1, f"Monolith 'rm': {args}")
    
        for cname in args:
            if not is_created(cname):
                print(f"'{cname}' isn't created, skipping")
                continue
            s = get_status(cname)
            if s:
                print(f"'{cname}' not dead enough to remove, skipping")
                continue
            mdir = f"{monolith_dir}/{cname}"
            shutil.rmtree(mdir)
            print(f"'{cname}' removed")
    
    else:
        bail(f"unrecognized monolith command: {cmd}")
