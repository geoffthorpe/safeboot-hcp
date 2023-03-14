import os
import sys
import subprocess
import re
import json
import time

sys.path.insert(1, '/hcp/common')
from hcp_common import log, bail, env_get, env_get_or_none, http2exit, \
	hcp_config_extract

enrollsvc_ctx = hcp_config_extract('.enrollsvc', must_exist = True)

# The two non-root users we may be acting on behalf of
dbuser = 'emgmtdb'
if 'dbuser' in enrollsvc_ctx:
	dbuser = enrollsvc_ctx['dbuser']
webuser = 'emgmtflask'
if 'emgmtflask' in enrollsvc_ctx:
	webuser = enrollsvc_ctx['webuser']

# The following environment elements are required by all db ops
enrollsvc_state = enrollsvc_ctx['state']
db_dir = f"{enrollsvc_state}/db"
repo_name = 'enrolldb.git'
repo_path = f"{db_dir}/{repo_name}"
repo_lockdir = f"{db_dir}/lock-{repo_name}"
ek_basename = 'ekpubhash'
ek_path = f"{repo_path}/{ek_basename}"
hn2ek_basename = 'hn2ek'
hn2ek_path = f"{repo_path}/{hn2ek_basename}"
valid_ekpubhash_re = '[a-f0-9_-]{64}'
valid_ekpubhash_prefix_re = '[a-f0-9_-]*'
valid_ekpubhash_prog = re.compile(valid_ekpubhash_re)
valid_ekpubhash_prefix_prog = re.compile(valid_ekpubhash_prefix_re)
class HcpEkpubhashError(Exception):
	pass

def valid_ekpubhash(ekpubhash):
	if not valid_ekpubhash_prog.fullmatch(ekpubhash):
		raise HcpEkpubhashError(
			f"HCP, invalid ekpubhash: {ekpubhash}")

def valid_ekpubhash_prefix(ekpubhash):
	if not valid_ekpubhash_prefix_prog.fullmatch(ekpubhash):
		raise HcpEkpubhashError(
			f"HCP, invalid ekpubhash prefix: {ekpubhash}")

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
	# ("I kill -9'd the service, restarted, and now it's not accepting
	# enrollments, plus there's a weird "lock" directory in the repo...")
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
def hn2ek_new():
	return []
def __hn2ek_sort_cb(entry):
	return entry['hostname']
def hn2ek_sort(data):
	data.sort(key = __hn2ek_sort_cb)
	return data
def hn2ek_read():
	with open(hn2ek_path, 'r') as f:
		return json.load(f)
def hn2ek_write(data):
	with open(hn2ek_path, 'w') as f:
		return json.dump(hn2ek_sort(data), f)
def hn2ek_query(data, hostname_regex):
	hostname_prog = re.compile(hostname_regex)
	results = []
	for i in data:
		if hostname_prog.search(i['hostname']):
			results += [i]
	return results
def hn2ek_add(data, hostname, ekpubhash):
	return data + [ { 'hostname': hostname, 'ekpubhash': ekpubhash } ]
def hn2ek_delete(data, hostname, ekpubhash):
	x = { 'hostname': hostname, 'ekpubhash': ekpubhash }
	return [i for i in data if i != x]
def hn2ek_xquery(hostname_regex):
	return hn2ek_query(hn2ek_read(), hostname_regex)
def hn2ek_xadd(hostname, ekpubhash):
	data = hn2ek_add(hn2ek_read(), hostname, ekpubhash)
	hn2ek_write(data)
def hn2ek_xdelete(hostname, ekpubhash):
	data = hn2ek_delete(hn2ek_read(), hostname, ekpubhash)
	hn2ek_write(data)

class HcpGitError(Exception):
	pass

def __git_cmd(args):
	args = ['git'] + args
	expanded = ' '.join(map(str, args))
	log(f"Running '{expanded}'")
	c = subprocess.run(args,
		stdout = subprocess.PIPE,
		text = True)
	if c.returncode != 0:
		log(f"{c.stdout}")
		raise HcpGitError(f"Failed: {expanded}")
	return c

def git_commit(msg):
	c = __git_cmd(['status', '--porcelain'])
	if len(c.stdout) > 0:
		log('git_commit(): committing changes')
		__git_cmd(['add', '.'])
		__git_cmd(['commit', '-a', '-m', msg])
	else:
		log('git_commit(): no changes to commit')

def git_reset():
	__git_cmd(['reset', '--hard'])
	__git_cmd(['clean', '-f', '-d', '-x'])
