import os
import sys
import subprocess
import re
import json
from pathlib import Path

def log(s):
	print(s, file=sys.stderr)

def bail(s):
	log(f"FAIL: {s}")
	sys.exit(1)

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

# The following environment elements are required by all db ops
enrollsvc_state = env_get('HCP_ENROLLSVC_STATE')
db_dir = f"{enrollsvc_state}/db"
repo_name = 'enrolldb.git'
repo_path = f"{db_dir}/{repo_name}"
repo_lockdir = f"{db_dir}/lock-{repo_name}"
ek_basename = 'ekpubhash'
ek_path = f"{repo_path}/{ek_basename}"
hn2ek_basename = 'hn2ek'
hn2ek_path = f"{repo_path}/{hn2ek_basename}"

def halfhash(ekpubhash):
	return ekpubhash[:16]

def fpath_parent(ekpubhash):
	ply1 = ekpubhash[:2]
	ply2 = ekpubhash[:6]
	return f"{ek_path}/{ply1}/{ply2}"

def fpath_base(ekpubhash):
	return ekpubhash[:32]

def fpath(ekpubhash):
	return f"{fpath_parent(ekpubhash)}/{fpath_base(ekpubhash)}"

# When doing 'git rm -r <dir>' (during a delete), we want <dir> relative to the
# git repo top-level, not an absolute path in the filesystem. We could
# construct this from 'ekpubhash', but by the time this function is called,
# we've already done a bunch of ekpubhash->plyX stuff, so instead we do a
# prefix replacement on the already-known absolute path. Ie. we chop off the
# path to the git repo and replace it with "./".
def fpath_to_git(current_fpath):
	return f".{current_fpath[len(repo_path):]}"

# Given a prefix, figure out a wildcard to match on all matching fpaths
def fpath_mask(prefix):
	if len(prefix) < 2:
		return f"{ek_path}/{prefix}*/*/*"
	ply1 = prefix[:2]
	if len(prefix) < 6:
		return f"{ek_path}/{ply1}/{prefix}*/*"
	ply2 = prefix[:6]
	if len(prefix) < 32:
		return f"{ek_path}/{ply1}/{ply2}/{prefix}*"
	ply3 = prefix[:32]
	return f"{ek_path}/{ply1}/{ply2}/{ply3}"

def repo_lock():
	# We want to serialize all attempts to commit enrollments to the git
	# repo. We use directory-creation as a mutex. I know, this isn't
	# perfect. But it's pretty stable, doesn't add dependencies, and if
	# something catastrophic happens, it's easy for an admin to figure out.
	# (I kill -9'd the service, restarted, it's not accepting enrollments,
	# and there's a weird "lock" directory ...)
	while True:
		try:
			os.mkdir(repo_lockdir)
			break
		except FileExistsError:
			pass
		time.sleep(0.2)

def repo_unlock():
	os.rmdir(repo_lockdir)

# We use TPM ekpubhash to determine paths to files (including the "hostname"
# file), so the DB is inherently indexed by ekpubhash and inherently maps
# ekpubhash -> hostname. For "add", "delete", and "query" operations, the
# ekpubhash is the input and that makes sense. But we also want to support a
# more general lookup based on hostname, call "find". We could do that by
# iterating over the DB looking for matching hostnames, but have instead chosen
# to maintain a single-file associating ekpubhash with hostname (called
# "hn2ek", even though "hostname to ekpubhash" is not really how it's
# implemented any more). It's much faster for "find", and is justified by the
# fact that "query" is unaffected, and both "add" and "delete" are already such
# heavyweight procedures that updating the hn2ek file isn't a roadblock. More
# performant (but more complex) solutions could be used later, seeing as we
# already have the concept of a distinct index.
#
# Anyway, hn2ek_find() reads the file into a data structure before searching
# it, whereas the add and delete also rewrite the file after updating the
# structure. The caller holds a lock while we do this, so the read-then-write
# is fine (we don't require atomic updates), but we shouldn't try to be any
# smarter than statelessly going to the file-system for every interaction (no
# cached state).
#
# The format. In the same spirit of using git for the DB, we use JSON for the
# hn2ek file. It's annoying that this prevents us from having the data
# structure be a set of 2-tuples, say. (JSON can't encode sets at all, and its
# only way of encoding tuples are as lists, which won't match when we parse
# them back in.) Instead, we use an array, where each entry is a dict having
# exactly two key-value pairs - one for "ekpubhash", another for "hostname".
# Order is irrelevant, but we can't make it vanish.
def hn2ek_read():
	with open(hn2ek_path, 'r') as f:
		return json.load(f)
def hn2ek_write(data):
	with open(hn2ek_path, 'w') as f:
		return json.dump(data, f)
def hn2ek_query(data, hostname_regex):
	hostname_prog = re.compile(hostname_regex)
	results = []
	for i in data:
		if hostname_prog.search(i['hostname']):
			results += [i]
	return results
def hn2ek_add(data, hostname, ekpubhash):
	data += [ { 'hostname': hostname, 'ekpubhash': ekpubhash } ]
def hn2ek_delete(data, hostname, ekpubhash):
	x = { 'hostname': hostname, 'ekpubhash': ekpubhash }
	newdata = [i for i in data if i != x]
def hn2ek_xquery(hostname_regex):
	data = hn2ek_read()
	return hn2ek_query(data, hostname_regex)
def hn2ek_xadd(hostname, ekpubhash):
	data = hn2ek_read()
	hn2ek_add(data, hostname, ekpubhash)
	hn2ek_write(data)
def hn2ek_xdelete(hostname, ekpubhash):
	data = hn2ek_read()
	hn2ek_delete(data, hostname, ekpubhash)
	hn2ek_write(data)

# Code shared by "add" and "delete". Send any stdout to stderr
def run_git_cmd(args):
	args = ['git'] + args
	expanded = ' '.join(map(str, args))
	log(f"Running '{expanded}'")
	c = subprocess.run(args,
		stdout = subprocess.PIPE,
		text = True)
	if c.returncode != 0:
		print(c.stdout, file = sys.stderr)
		raise HcpErrorChildProcess(f"Failed: {expanded}")
