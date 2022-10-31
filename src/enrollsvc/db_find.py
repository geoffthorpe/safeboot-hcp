import sys
import os
import json

sys.path.insert(1, '/hcp/common')
from hcp_common import log

sys.path.insert(1, '/hcp/enrollsvc')
import db_common
bail = db_common.bail
http2exit = db_common.http2exit

# Usage:
# db_find.py <clientjson>
# where clientjson is;
#   {
#       'hostname_regex': <regular expression>
#   }

if len(sys.argv) != 2:
	bail(f"Wrong number of arguments: {len(sys.argv)}")

clientjson = sys.argv[1]
if len(clientjson) == 0:
	bail(f"Empty JSON")
# Don't error-check this, let the exceptions fly if there's anything wrong.
clientdata = json.loads(clientjson)

hostname_regex = clientdata['hostname_regex']

# Change working directory to the git repo
os.chdir(db_common.repo_path)

# Critical section, same basic idea as in db_add.py
db_common.repo_lock()
caught = None
try:
	hn2ek_data = db_common.hn2ek_read()
except Exception as e:
	caught = e
db_common.repo_unlock()
if caught:
	raise caught

entries = db_common.hn2ek_query(hn2ek_data, hostname_regex)

result = {
	'hostname_regex': hostname_regex,
	'entries': entries
}
print(json.dumps(result, sort_keys = True))
sys.exit(http2exit(200))
