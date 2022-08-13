import sys
import os
import re
import json
import glob

sys.path.insert(1, '/hcp/enrollsvc')
import db_common
log = db_common.log
bail = db_common.bail
run_git_cmd = db_common.run_git_cmd

valid_ekpubhash_prefix_re = '[a-f0-9_-]*'
valid_ekpubhash_prefix_prog = re.compile(valid_ekpubhash_prefix_re)
class HcpEkpubhashPrefixError(Exception):
	pass

# Usage:
# db_query.py <clientjson>
# where clientjson is;
#   {
#       'ekpubhash': <ekpubhash or prefix thereof>
#   }

if len(sys.argv) != 2:
	bail(f"Wrong number of arguments: {len(sys.argv)}")

clientjson = sys.argv[1]
if len(clientjson) == 0:
	bail(f"Empty JSON")
# Don't error-check this, let the exceptions fly if there's anything wrong.
clientdata = json.loads(clientjson)

# Extract the (possibly-empty) ekpubhash prefix
req_ekpubhash = clientdata['ekpubhash']
if not valid_ekpubhash_prefix_prog.fullmatch(req_ekpubhash):
	raise HcpEkpubhashPrefixError(
		f"HCP, invalid ekpubhash prefix: {req_ekpubhash}")

# Option on whether (or not) file-lists should be returned in the query response
no_files = clientdata['nofiles']

# Change working directory to the git repo
os.chdir(db_common.repo_path)

# Get a wildcard pattern for all matching entries
fpath = db_common.fpath_mask(req_ekpubhash)

# The array of matches that gets returned to the client (in JSON form)
entries = []

# The query logic doubles up as delete logic, based on an env-var
is_delete = ('QUERY_PLEASE_ALSO_DELETE' in os.environ)
if is_delete:
	cmdname = 'delete'
else:
	cmdname = 'query'

# Critical section, same basic idea as in db_add.py
db_common.repo_lock()
caught = None
try:
	matches = glob.glob(fpath)
	if is_delete:
		hn2ek_data = db_common.hn2ek_read()
	for path in matches:
		ekpubhash = open(f"{path}/ekpubhash", 'r').read()
		hostname = open(f"{path}/hostname", 'r').read()
		entry = {
			'ekpubhash': ekpubhash,
			'hostname': hostname
		}
		if not no_files:
			files = [ x[len(path)+1:] for x in glob.glob(f"{path}/*") ]
			files.sort()
			entry['files'] = files
		entries += [ entry ]
		if is_delete:
			# Remove the ekpubhash directory (and all its files)
			run_git_cmd(['rm', '-r', db_common.fpath_to_git(path)])
			# Remove the corresponding hn2ek entry
			db_common.hn2ek_delete(hn2ek_data,
					       hostname,
					       ekpubhash)
	if is_delete and len(matches) > 0:
		# Write the updated hn2ek data and add include it in the
		# impending commit
		db_common.hn2ek_write(hn2ek_data)
		run_git_cmd(['add', db_common.hn2ek_basename])
		# Commit the accumulated changes
		run_git_cmd(['commit', '-m', f"delete {req_ekpubhash}"])
except Exception as e:
	caught = e
	log(f"Failed: enrollment DB '{cmdname}': {caught}")
	# recover the git repo before we release the lock
	try:
		run_git_cmd(['reset', '--hard'])
		run_git_cmd(['clean', '-f', '-d', '-x'])
	except Exception as e:
		log(f"Failed: enrollment DB rollback: {e}")
		bail(f"CATASTROPHIC! DB stays locked for manual intervention")
		raise caught
	log(f"Enrollment DB rollback complete")

# Remove the lock, then reraise any exception we intercepted
db_common.repo_unlock()
if caught:
	log(f"Enrollment DB exception continuation: {caught}")
	raise caught

# The point of this entire file: produce a JSON to stdout that confirms the
# transaction. This gets returned to the client. NB: we could've just encoded
# the 'entries' list directly to JSON, rather than putting it as the only field
# inside a dict, but that would involve going back in time (or changing any/all
# affected client code). Maybe later, if/when we need to change the API for
# some other reason.
result = {
	'entries': entries
}
print(json.dumps(result))
