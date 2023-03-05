import os
import sys
import json
import psutil
import pwd
import glob
import subprocess
import getpass
from pathlib import Path
from datetime import datetime, timezone, timedelta

sys.path.insert(1, '/hcp/xtra')
import HcpJsonPath

# Equivalent for the 'touch' command
def touch(p, *, makedirs = True):
	if makedirs:
		d = os.path.dirname(p)
		if not os.path.isdir(d):
			os.makedirs(d, mode = 0o755)
	with open(p, 'a'):
		os.utime(p, None)

# This is rudimentary: level 0 is for stuff that will go to stderr no matter
# what, level 1 is for stuff that should go to stderr if you actually want to
# debug anything, and level 2 is for stuff whose absence might be desirable if
# someone is debugging but wants less of a firehose.
#
# - def_loglevel is the log level to assume for callers to log()
# - current_loglevel is the maximum level to let through to stderr (anything
#   higher is dropped)
# - cfg_trace is an optional dict that will exist if a '.trace' field exists in
#   the current config (and scope). When it exists, we make decisions on where
#   and how to log.
# - current_log_path remembers the last time we opened a tracefile and assigned
#   it to sys.stderr. The logging code will determine what the tracefile should
#   be (None, unless cfg_trace is set) and compare it with current_log_path -
#   if they're different, a new tracefile needs to be opened and assigned.
def_loglevel = 1
current_loglevel = 0
current_log_path = None
current_tracefile = None

if 'VERBOSE' in os.environ:
	current_loglevel = int(os.environ['VERBOSE'])

def logrotate():
	global current_log_path
	global current_tracefile
	if 'HCP_NOTRACEFILE' in os.environ:
		return
	uid = os.geteuid()
	whoami = pwd.getpwuid(uid).pw_name
	now = datetime.now(timezone.utc)
	pid = os.getpid()
	procname = '_unknown_'
	for proc in psutil.process_iter(['pid', 'name']):
		if proc.info['pid'] == pid:
			procname = proc.info['name']
			break
	dtdir = f"{now.year:04}-{now.month:02}-{now.day:02}-{now.hour:02}"
	dtf = f"{now.minute:02}-{now.second:02}"
	fdir = f"/tmp/debug-{whoami}-{dtdir}"
	fname = f"{fdir}/{dtf}-{procname}.{pid}"
	if current_log_path != fname:
		try:
			os.makedirs(fdir, mode = 0o755)
		except FileExistsError:
			pass
		tracefile = open(f"{fname}", 'a')
		if current_log_path or current_loglevel > 1:
			print(f"[tracefile forking to {fname}]", file = sys.stderr)
		sys.stderr.flush()
		sys.stderr = tracefile
		print(f"[tracefile forked from {current_log_path}]",
			file = sys.stderr)
		sys.stderr.flush()
		current_log_path = fname
		current_tracefile = tracefile

def hlog(level, s):
	global current_loglevel
	if level > current_loglevel:
		return
	logrotate()
	print(s, file = sys.stderr)
	sys.stderr.flush()

def log(s):
	global def_loglevel
	hlog(def_loglevel, s)

def bail(s, exitcode = 1):
	hlog(0, f"FAIL: {s}")
	sys.exit(exitcode)

# - HCP_CONFIG_FILE is the path to the JSON config file.
# - HCP_CONFIG_SCOPE is where we are currently 'nested' within that JSON.
# - hcp_config_extract() pulls fields from the JSON, at the given path, and
#   relative to HCP_CONFIG_SCOPE.
# - hcp_config_scope_shrink() pushes a new sub-path, and updates
#   HCP_CONFIG_SCOPE accordingly.
# Note that hcp_config_*() functions will handle a path that has no leading '.'
workloadpath = '/tmp/workloads'
if 'HCP_CONFIG_FILE' not in os.environ:
	# TODO: hcp.sh handles cases we don't - probably want to change its use
	# of a bash-sourcible file to something python can consume too. Eg. it
	# could write env-vars to a JSON file, which both bash(+jq) and python
	# could handle.
	hlog(1, "Warning, no HCP_CONFIG_FILE, use of APIs may 'exit'")
else:
	curpath = os.environ['HCP_CONFIG_FILE']
	if curpath.startswith(workloadpath) or curpath.startswith('/etc'):
		hlog(2, f"hcp_config: already relocated ({curpath})")
	else:
		username = getpass.getuser()
		if username != 'root':
			hlog(0, f"Warning, HCP_CONFIG_FILE ({curpath}) not relocated")
		else:
			filename = os.path.basename(curpath)
			newpath = f"{workloadpath}/{filename}"
			hlog(2, "hcp_config: relocating")
			hlog(2, f"- from: {curpath}")
			hlog(2, f"-   to: {newpath}")
			os.makedirs(workloadpath, exist_ok = True, mode = 0o755)
			world = json.load(open(curpath, 'r'))
			with open(newpath, 'w') as f:
				json.dump(world, f)
			os.environ['HCP_CONFIG_FILE'] = newpath
def hcp_config_scope_set(path):
	if 'HCP_CONFIG_FILE' not in os.environ:
		raise Exception("!HCP_CONFIG_FILE")
	world = json.load(open(os.environ['HCP_CONFIG_FILE'], 'r'))
	if not path.startswith('.'):
		path = f".{path}"
	hlog(2, f"hcp_config_scope_set: {path}")
	_ = HcpJsonPath.extract_path(world, path, must_exist = True)
	os.environ['HCP_CONFIG_SCOPE'] = path
def hcp_config_scope_get():
	if 'HCP_CONFIG_FILE' not in os.environ:
		raise Exception("!HCP_CONFIG_FILE")
	# If HCP_CONFIG_SCOPE isn't set, it's possible we're the first context
	# started. In which case the world we're given is supposed to be our
	# starting context, in which case our initial region is ".".
	if 'HCP_CONFIG_SCOPE' not in os.environ:
		hlog(2, "hcp_config_scope_get: no HCP_CONFIG_SCOPE")
		# OTOH, if HCP_CONFIG_FILE isn't set _either_, the only legit
		# explanation is that privileges have been dropped or switched
		# and we're coming up as a regular user and need to find
		# context. In this case, we try;
		# - $HOME/hcp_config_file.
		# - /etc/hcp-monolith-container.env, see
		#   src/hcp/monolith/set_container_env.sh.
		if 'HCP_CONFIG_FILE' not in os.environ:
			home = ''
			_global = "/etc/hcp-monolith-container.env"
			if 'HOME' in os.environ:
				home = os.environ['HOME']
			worldfile = f"{home}/hcp_config_file"
			pathfile = f"{home}/hcp_config_scope"
			if os.path.isfile(worldfile):
				hlog(2, f"- setting HCP_CONFIG_FILE to {worldfile}")
				os.environ['HCP_CONFIG_FILE'] = worldfile
				if os.path.isfile(pathfile):
					hlog(2, f"- setting HCP_CONFIG_SCOPE to {pathfile}")
					hcp_config_scope_set(open(pathfile,
							'r').read().strip())
			elif os.path.isfile(_global):
				hlog(2, f"- loading {_global}")
				lines = open(_global, 'r').readlines()
				for l in lines:
					if not l.startswith('export HCP_'):
						continue
					kv = l.replace('export ', '').split('=', 1)
					hlog(2, f"  - setting {kv[0]}={kv[1]}")
					os.environ[kv[0]] = kv[1]
			else:
				bail("Error, no HCP_CONFIG_FILE set")
		# If the path still isn't set, default to '.'
		if 'HCP_CONFIG_SCOPE' not in os.environ:
			hlog(2, "- defaulting HCP_CONFIG_SCOPE to '.'")
			hcp_config_scope_set('.')
	result = os.environ['HCP_CONFIG_SCOPE']
	hlog(2, f"hcp_config_scope_get: returning {result}")
	return result
def hcp_config_scope_shrink(path):
	if 'HCP_CONFIG_FILE' not in os.environ:
		raise Exception("!HCP_CONFIG_FILE")
	if not path.startswith('.'):
		path = f".{path}"
	hlog(2, f"hcp_config_scope_shrink: {path}")
	hcp_config_scope_get()
	full_path = os.environ['HCP_CONFIG_SCOPE']
	if full_path == '.':
		full_path = path
	elif path != '.':
		full_path = f"{full_path}{path}"
	hcp_config_scope_set(full_path)
# Don't forget, this API shares semantics with HcpJsonPath.extract_path(). Most
# notably, it returns a 2-tuple by default;
#  (boolean success, {dict|list|str|int|None} resultdata)
# unless you set 'must_exist=True' or 'or_default=True'. If 'must_exist' is
# set, this returns only result data and throws an exception if the path
# doesn't exist. If 'or_default' is set, it likewise returns only result data
# and returns a default value if the path doesn't exist. (The default default
# (!) is 'None', but this can be altered by specifying 'default=<val>'.)
def hcp_config_extract(path, **kwargs):
	if 'HCP_CONFIG_FILE' not in os.environ:
		raise Exception("!HCP_CONFIG_FILE")
	if not path.startswith('.'):
		path = f".{path}"
	hlog(3, f"hcp_config_extract: {path}")
	hcp_config_scope_get()
	full_path = os.environ['HCP_CONFIG_SCOPE']
	if full_path == '.':
		full_path = path
	elif path != '.':
		full_path = f"{full_path}{path}"
	world = json.load(open(os.environ['HCP_CONFIG_FILE'], 'r'))
	return HcpJsonPath.extract_path(world, full_path, **kwargs)

def env_get(k):
	if not k in os.environ:
		bail(f"Missing environment variable: {k}")
	v = os.environ[k]
	if not isinstance(v, str):
		bail(f"Environment variable not a string: {k}:{v}")
	return v

def env_get_or_none(k):
	if not k in os.environ:
		return None
	v = os.environ[k]
	if not isinstance(v, str):
		return None
	if len(v) == 0:
		return None
	return v

def env_get_dir_or_none(k):
	v = env_get_or_none(k)
	if not v:
		return None
	path = Path(v)
	if not path.is_dir():
		return None
	return v

def env_get_dir(k):
	v = env_get(k)
	path = Path(v)
	if not path.is_dir():
		bail(f"Environment variable not a directory: {k}:{v}")
	return v

def env_get_file(k):
	v = env_get(k)
	path = Path(v)
	if not path.is_file():
		bail(f"Environment variable not a file: {k}:{v}")
	return v

def dict_val_or(d, k, o):
	if k not in d:
		return o
	return d[k]

def dict_pop_or(d, k, o):
	if k not in d:
		return o
	return d.pop(k)

# Given a dict, extract whichever of 'years', 'months', 'weeks', 'days',
# 'hours', 'minutes', 'seconds' are defined (as integers) and return a
# timedelta corresponding to the aggregate total.
def dict_timedelta(d):
	def get_int_or_none(k):
		ret = dict_val_or(d, k, None)
		if ret and not isinstance(ret, int):
			bail(f"Wrong type for {k} property: {type(ret)},{ret}")
		return ret
	td = timedelta()
	conf_years = get_int_or_none('years')
	conf_months = get_int_or_none('months')
	conf_weeks = get_int_or_none('weeks')
	conf_days = get_int_or_none('days')
	conf_hours = get_int_or_none('hours')
	conf_minutes = get_int_or_none('minutes')
	conf_seconds = get_int_or_none('seconds')
	if conf_years:
		td += timedelta(days = conf_years * 365)
	if conf_months:
		td += timedelta(days = conf_months * 28)
	if conf_weeks:
		td += timedelta(days = conf_weeks * 7)
	if conf_days:
		td += timedelta(days = conf_days)
	if conf_hours:
		td += timedelta(hours = conf_hours)
	if conf_minutes:
		td += timedelta(minutes = conf_minutes)
	if conf_seconds:
		td += timedelta(seconds = conf_seconds)
	return td

# Given a datetime, produce a string of the form "YYYYMMDDhhmmss" that can
# be used in a filename/path. This gives 1-second granularity and gives
# useful outcomes when such strings get sorted alphabetically.
def datetime2hint(dt):
	s = f"{dt.year:04}{dt.month:02}{dt.day:02}"
	s += f"{dt.hour:02}{dt.minute:02}{dt.second:02}"
	return s

# See the comments for http2exit and exit2http in common/hcp.sh, this is simply
# a python version of the same.
ahttp2exit = {
	200: 20, 201: 21,
	400: 40, 401: 41, 403: 43, 404: 44,
	500: 50
}
aexit2http = {
	20: 200, 21: 201,
	40: 400, 41: 401, 43: 403, 44: 404,
	50: 500, 49: 500, 0: 200
}
def alookup(a, k, d):
	if k in a:
		v = a[k]
	else:
		v = d
	return v
def http2exit(x):
	return alookup(ahttp2exit, x, 49)
def exit2http(x):
	return alookup(aexit2http, x, 500)

def add_install_path(d):
	def _add_path(n, vs):
		current = ''
		if n in os.environ:
			current = os.environ[n]
		for v in vs:
			if not os.path.isdir(v):
				continue
			if len(current) > 0:
				current = f"{current}:{v}"
			else:
				current = v
		os.environ[n] = current
	_add_path('PATH',
		[ f"{d}/bin", f"{d}/sbin", f"{d}/libexec" ])
	_add_path('LD_LIBRARY_PATH',
		[ f"{d}/lib", f"{d}/lib/python/dist-packages" ])

installdirs = glob.glob('/install-*')
for i in installdirs:
	add_install_path(i)
