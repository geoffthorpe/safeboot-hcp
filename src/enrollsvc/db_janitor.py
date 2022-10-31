import sys
import os
import json
import glob

sys.path.insert(1, '/hcp/common')
import hcp_common
log = hcp_common.log
http2exit = hcp_common.http2exit

sys.path.insert(1, '/hcp/enrollsvc')
import db_common
bail = db_common.bail
git_commit = db_common.git_commit
git_reset = db_common.git_reset

if len(sys.argv) != 1:
	bail(f"Wrong number of arguments: {len(sys.argv)}")

log("db_janitor: starting in {db_common.repo_path}")
# Change working directory to the git repo
os.chdir(db_common.repo_path)

# Get a wildcard pattern for all matching entries
fpath = db_common.fpath_mask('')
log(f"db_janitor: fpath={fpath}")

# This function gets run on each DB entry and is expected to return a 2-tuple
# of the (possibly-altered) ekpubhash and hostname.
def scrub_entry(path):
	ekpubhash = open(f"{path}/ekpubhash", 'r').read()
	hostname = open(f"{path}/hostname", 'r').read()
	# This could be soooo much more ... umm ... 'validating'. Right now
	# we're only looking out for known problems, namely that ekpubhash and
	# hostname shouldn't be \n-terminated.
	log(f"db_janitor:  prescrub: ekpubhash={ekpubhash}, hostname={hostname}")
	ekpubhash = ekpubhash.replace('\n', '')
	hostname = hostname.replace('\n', '')
	log(f"db_janitor: postscrub: ekpubhash={ekpubhash}, hostname={hostname}")
	open(f"{path}/ekpubhash", 'w').write(f"{ekpubhash}")
	open(f"{path}/hostname", 'w').write(f"{hostname}")
	return ekpubhash, hostname

# Critical section, same basic idea as in db_add.py
db_common.repo_lock()
caught = None
try:
	hn2ek = db_common.hn2ek_new()
	matches = glob.glob(fpath)
	log(f"db_janitor: matches={matches}")
	for path in matches:
		log(f"db_janitor: loop start, path={path}")
		ekpubhash, hostname = scrub_entry(path)
		hn2ek += [ { 'hostname': hostname, 'ekpubhash': ekpubhash } ]
	db_common.hn2ek_write(hn2ek)
	git_commit("Janitor")
except Exception as e:
	caught = e
	log(f"db_janitor: failed enrollment DB update: {caught}")
	# recover the git repo before we release the lock
	try:
		git_reset()
	except Exception as e:
		log(f"db_janitor: failed to recover!: {e}")
		bail(f"CATASTROPHIC! DB stays locked for manual intervention")
	log(f"db_janitor: enrollment DB rollback complete")

# Remove the lock, then reraise any exception we intercepted
db_common.repo_unlock()
if caught:
	log(f"db_janitor: enrollment DB exception continuation: {caught}")
	raise caught

result = json.dumps({ 'hn2ek': hn2ek}, sort_keys = True)
log(f"db_janitor: emitting result={result}")
print(result)
sys.exit(http2exit(200))
