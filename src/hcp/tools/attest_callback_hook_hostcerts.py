#!/usr/bin/python3

# This post-processing hook can be invoked from the common attest callback by
# pointing HCP_ATTESTCLIENT_HOOK_HOSTCERTS to it. It allows the owner to
# specify a set of regex-driven rules to apply when processing the HCP-issued
# assets after attestation, and for those assets that match, specify locations
# to copy those files to, and (most importantly) which user the files should be
# owned by.
#
# When invoked;
# - stdin is a JSON document containing an array of assets, as per the pre and
#   post install hooks used with attest_callback_common.py.
# - if HCP_HOSTCERTS_MAPFILE is defined, it must be the path to a file
#   consisting of a JSON list of rules, with each rule being a dict of the
#   form;
#   [
#      {
#         'regex': <regex>,      <-- required
#         'dest': <path>,        <-- required
#         'owner': <username>,   <-- optional, defaults to 'root'
#         'mode': <octalstring>, <-- optional, defaults to '640'
#      }
#   ]
# - otherwise, if HCP_HOSTCERTS_MAP is defined (not "MAPFILE", "MAP"), it must
#   hold the literal JSON text of the same array of rules.
#
# For assets that match a regex, the file will be copied, the owner will be
# modified, and then the destination path will be atomically updated. The rules
# are processed in order, and once an asset has matched, it is not compared
# with any subsequent rules.

import os
import sys
import json
import re
import pwd
import shutil
import filecmp

def doprint(s):
	print(s, file = sys.stderr)

assets = json.load(sys.stdin)

rules = None
if 'HCP_HOSTCERTS_MAPFILE' in os.environ:
	mpath = os.environ['HCP_HOSTCERTS_MAPFILE']
	if not os.path.isfile(mpath):
		doprint(f"Error, '{mpath}' (HCP_HOSTCERTS_MAPFILE) doesn't exist")
		sys.exit(1)
	with open(mpath, 'r') as fp:
		rules = json.load(fp)
elif 'HCP_HOSTCERTS_MAP' in os.environ:
	rawjson = os.environ['HCP_HOSTCERTS_MAP']
	rules = json.loads(rawjson)
else:
	sys.exit(0)

if not isinstance(rules, list):
	doprint(f"Error, rules JSON should be a list (not {type(rules)})")
	sys.exit(1)

# Parse the rules, precompile the regexs, convert owner names to uids, etc
newrules = []
for i in rules:
	if not isinstance(i, dict):
		doprint(f"Error, rules entry should be dict (not {type(i)})")
		sys.exit(1)
	if 'regex' not in i:
		doprint(f"Error, rules entry has no 'regex' attribute")
		sys.exit(1)
	if 'dest' not in i:
		doprint(f"Error, rules entry has no 'dest' attribute")
		sys.exit(1)
	if 'owner' not in i:
		i['owner'] = 'root'
	if 'mode' not in i:
		i['mode'] = '640'
	i['prog'] = re.compile(i['regex'])
	# If this rule covers assets intended for a user that doesn't exist
	# _yet_, bypass the rule _this time_. Eg. if the rules and assets are
	# statically defined and therefore present at all times, but package
	# installations and account creations occur at run-time, then this
	# generally gives the desired behavior. (Once the operator has caused
	# the relevant accounts to be created, they can explicitly trigger the
	# 'run_client.sh' tool to wait for another attestation loop to be
	# processed, thus ensuring the now-actionable rules have taken effect.)
	try:
		i['uid'] = pwd.getpwnam(i['owner']).pw_uid
		newrules += [ i ]
	except KeyError:
		doprint(f"Bypassing, non-existent owner '{i['owner']}'")
rules = newrules

# Run through the assets, looking for matches. Note, the 'is_changed' value
# in each asset record is with respect to whether the underlying attestation processing
# received an asset that is new or different to what it might have received previously.
# That has no bearing on whether _we_ have processed it before, eg. in the case where
# rules change or accounts come and go.
for a in assets:
	name = a['name']
	# Find the first match, if any
	_match = None
	for i in rules:
		regex = i['regex']
		prog = i['prog']
		if prog.fullmatch(name):
			doprint(f"Info, asset '{name}' matched '{regex}'")
			_match = i
			break
	if not _match:
		doprint(f"Info, asset '{name}' didn't match any rules")
		continue
	olddest = a['dest']
	newdest = _match['dest']
	bdir = os.path.dirname(newdest)
	if not os.path.isdir(bdir):
		doprint(f"Info, mkdir -p '{bdir}'")
		os.makedirs(bdir, mode = 0o755)
	if os.path.isfile(newdest) and filecmp.cmp(olddest, newdest):
		doprint(f"Info, asset unchanged, skipping")
		continue
	tmpdest = f"{newdest}.tmp"
	uid = _match['uid']
	doprint(f"Info, copying '{olddest}' to '{tmpdest}'")
	shutil.copyfile(olddest, tmpdest)
	doprint(f"Info, chowning '{tmpdest}' to UID {uid}")
	os.chown(tmpdest, uid, -1)
	doprint(f"Info, moving '{tmpdest}' to '{newdest}'")
	os.rename(tmpdest, newdest)
