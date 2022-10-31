import sys
import os
import re
import json
import glob
import shutil

sys.path.insert(1, '/hcp/common')
import hcp_common
log = hcp_common.log
http2exit = hcp_common.http2exit

sys.path.insert(1, '/hcp/enrollsvc')
import db_common
git_commit = db_common.git_commit
git_reset = db_common.git_reset
bail = db_common.bail

# Usage:
# db_query.py <clientjson>
# where clientjson is;
#   {
#       'ekpubhash': <ekpubhash or prefix thereof>
#   }

if len(sys.argv) != 2:
	bail(f"Wrong number of arguments: {len(sys.argv)}")

clientjson = sys.argv[1]
log(f"db_querydelete: using clientjson={clientjson}")
if len(clientjson) == 0:
	bail(f"Empty JSON")
# Don't error-check this, let the exceptions fly if there's anything wrong.
clientdata = json.loads(clientjson)
log(f"db_querydelete: clientdata={clientdata}")

# Extract the (possibly-empty) ekpubhash prefix
req_ekpubhash = clientdata['ekpubhash']
log(f"db_querydelete: req_ekpubhash={req_ekpubhash}")
db_common.valid_ekpubhash_prefix(req_ekpubhash)

# Option on whether (or not) file-lists should be returned in the query response
no_files = clientdata['nofiles']
log(f"db_querydelete: no_files={no_files}")

# Change working directory to the git repo
os.chdir(db_common.repo_path)

# Get a wildcard pattern for all matching entries
fpath = db_common.fpath_mask(req_ekpubhash)
log(f"db_querydelete: fpath={fpath}")

# The array of matches that gets returned to the client (in JSON form)
entries = []

# The query logic doubles up as delete logic, based on an env-var
is_delete = ('QUERY_PLEASE_ALSO_DELETE' in os.environ)
if is_delete:
	cmdname = 'delete'
else:
	cmdname = 'query'
log(f"db_{cmdname}: cmdname={cmdname}")

# Critical section, same basic idea as in db_add.py
db_common.repo_lock()
caught = None
try:
	matches = glob.glob(fpath)
	log(f"db_{cmdname}: matches={matches}")
	for path in matches:
		log(f"db_{cmdname}: loop start, path={path}")
		ekpubhash = open(f"{path}/ekpubhash", 'r').read().strip('\n')
		hostname = open(f"{path}/hostname", 'r').read().strip('\n')
		entry = {
			'ekpubhash': ekpubhash,
			'hostname': hostname
		}
		log(f"db_{cmdname}: entry={entry}")
		if not no_files:
			files = [ x[len(path)+1:] for x in glob.glob(f"{path}/*") ]
			files.sort()
			entry['files'] = files
		entries += [ entry ]
		if is_delete:
			# Remove the ekpubhash directory (and all its files)
			shutil.rmtree(path)
			# Remove the corresponding hn2ek entry
			log(f"db_{cmdname}: delete, hostname={hostname}, ekpubhash={ekpubhash}")
			log(f"db_{cmdname}:  pre: hn2ek={db_common.hn2ek_read()}")
			db_common.hn2ek_xdelete(hostname, ekpubhash)
			log(f"db_{cmdname}: post: hn2ek={db_common.hn2ek_read()}")
	git_commit(f"delete {req_ekpubhash}")
except Exception as e:
	caught = e
	log(f"db_{cmdname}: failed enrollment DB '{cmdname}': {caught}")
	# recover the git repo before we release the lock
	try:
		git_reset()
	except Exception as e:
		log(f"db_{cmdname}: failed to recover!: {e}")
		bail(f"CATASTROPHIC! DB stays locked for manual intervention")
	log(f"db_{cmdname}: enrollment DB rollback complete")

# Remove the lock, then reraise any exception we intercepted
db_common.repo_unlock()
if caught:
	log(f"db_{cmdname}: enrollment DB exception continuation: {caught}")
	raise caught

# The point of this entire file: produce a JSON to stdout that confirms the
# transaction. This gets returned to the client. NB: we could've just encoded
# the 'entries' list directly to JSON, rather than putting it as the only field
# inside a dict, but that would involve going back in time (or changing any/all
# affected client code). Maybe later, if/when we need to change the API for
# some other reason.
result = json.dumps({ 'entries': entries }, sort_keys = True)
log(f"db_{cmdname}: emitting result={result}")
print(result)
sys.exit(http2exit(200))
