import sys
import os
import json
import requests
import shutil
import subprocess
import time
import hashlib
from tempfile import TemporaryDirectory
from uuid import uuid4

sys.path.insert(1, '/hcp/xtra')

from HcpHostname import valid_hostname, dc_hostname, pop_hostname
from HcpRecursiveUnion import union
import HcpEnvExpander

sys.path.insert(1, '/hcp/enrollsvc')
import db_common
log = db_common.log
bail = db_common.bail
run_git_cmd = db_common.run_git_cmd

# IMPORTANT: this file must send any miscellaneous output to stderr _only_.
# This process is launched (by mgmt_sudo.sh) behind a 'sudo' call from the
# web-app, which is expecting JSON output to show up on stdout when we exit
# (unless we exit non-zero). Anything else that goes to stdout will likely
# corrupt the JSON.

class HcpErrorChildProcess(Exception):
	pass
class HcpErrorTPMalreadyEnrolled(Exception):
	pass

# Usage:
# db_add.py <path-to-ekpub> <hostname> <clientjson>

if len(sys.argv) != 4:
	bail(f"Wrong number of arguments: {len(sys.argv)}")

path_ekpub = sys.argv[1]
if not os.path.exists(path_ekpub):
	bail(f"No file at ekpub path: {path_ekpub}")

hostname = sys.argv[2]
valid_hostname(hostname)

clientjson = sys.argv[3]
if len(clientjson) == 0:
	bail(f"Empty JSON")
# Don't error-check this, let the exceptions fly if there's anything wrong.
clientdata = json.loads(clientjson)

# We also expect these env-vars to point to things
signing_key_dir = db_common.env_get_dir('SIGNING_KEY_DIR')
signing_key_pub = db_common.env_get_file('SIGNING_KEY_PUB')
signing_key_priv = db_common.env_get_file('SIGNING_KEY_PRIV')
gencert_ca_dir = db_common.env_get_dir('GENCERT_CA_DIR')
gencert_ca_cert = db_common.env_get_file('GENCERT_CA_CERT')
gencert_ca_priv = db_common.env_get_file('GENCERT_CA_PRIV')

# Make sure attest-enroll prefers HCP's genprogs
genprogspath = '/hcp/enrollsvc/genprogs'
if 'PATH' in os.environ:
	genprogspath=f"{genprogspath}:{os.environ['PATH']}"
os.environ['PATH']=genprogspath

# Enroll in a temp directory that gets automatically cleaned up
ephemeral_dir_obj = TemporaryDirectory()
ephemeral_dir = ephemeral_dir_obj.name
os.environ['EPHEMERAL_ENROLL'] = ephemeral_dir

# Load the server's config and extract the "preclient" and "postclient"
# profiles. Again, we let exceptions do our error-checking
serverprofile = {}
if 'HCP_ENROLLSVC_JSON' in os.environ:
	configpath = os.environ['HCP_ENROLLSVC_JSON']
	serverprofile = json.load(open(configpath, 'r'))
serverprofile_pre = serverprofile.pop('preclient', {})
serverprofile_post = serverprofile.pop('postclient', {})

# Now merge with the client. Basically this is a non-shallow merge, in which
# the client's (requested) profile is overlaid on the server's "preclient"
# profile, and then the server's "postclient" profile is overlaid on top of
# that.
resultprofile = union(union(serverprofile_pre, clientdata), serverprofile_post)

# Need to add some "env" elements to support expansion
# - force the ENROLL_HOSTNAME variable from our inputs
# - also add application config that comes to us from env-vars but may be
#   needed in substitution.
# - calculate derivative environment variables that we make available for
#   parameter-expansion.
hostname2dc = dc_hostname(hostname)
domain = ""
if 'ENROLL_DOMAIN' in resultprofile['__env']:
	domain = resultprofile['__env']['ENROLL_DOMAIN']
else:
	_, domain = pop_hostname(hostname)
	resultprofile['__env']['ENROLL_DOMAIN'] = domain
domain2dc = dc_hostname(domain)
xtra_env = {
	'__env': {
		'ENROLL_HOSTNAME': f"{hostname}",
		'SIGNING_KEY_DIR': f"{signing_key_dir}",
		'SIGNING_KEY_PUB': f"{signing_key_pub}",
		'SIGNING_KEY_PRIV': f"{signing_key_priv}",
		'GENCERT_CA_DIR': f"{gencert_ca_dir}",
		'GENCERT_CA_CERT': f"{gencert_ca_cert}",
		'GENCERT_CA_PRIV': f"{gencert_ca_priv}",
		'ENROLL_HOSTNAME2DC': f"{hostname2dc}",
		'ENROLL_DOMAIN2DC': f"{domain2dc}"
	}
}
resultprofile=union(resultprofile, xtra_env)

# Now we need to perform parameter-expansion
origenv = resultprofile.pop('__env', {})
data_no_env = json.dumps(resultprofile)
HcpEnvExpander.env_check(origenv)
envjson, env = HcpEnvExpander.env_selfexpand(origenv)
data_no_env = HcpEnvExpander.env_expand(data_no_env, env)
result_profile = json.loads(data_no_env)
result_profile['__env'] = origenv
os.environ['ENROLL_JSON'] = json.dumps(result_profile)

# The JSON profile is now fully curated. (The only thing left to do is generate
# the enroll.conf that safeboot's 'attest-enroll' requires, but that's only
# because it doesn't consume our profile.)
# So before doing that and performing the enrollment, send our profile to the
# policy-checker!
policy_url = db_common.env_get_or_none('HCP_ENROLLSVC_POLICY')
if policy_url:
	uuid = uuid4().urn
	os.environ['HCP_REQUEST_UID'] = uuid
	form_data = {
		'hookname': (None, 'enrollsvc::mgmt::client_check'),
		'request_uid': (None, uuid),
		'params': (None, json.dumps(resultprofile))
	}
	url = f"{policy_url}/v1/add"
	response = requests.post(url, files=form_data)
	if response.status_code != 200:
		bail(f"policy-checker refused enrollment: {response.status_code}")

# Prepare that enroll.conf that safeboot feeds on
genprogs_pre = ""
genprogs_post = ""
genprogs = ""
if 'genprogs_pre' in resultprofile:
	genprogs_pre = resultprofile['genprogs_pre']
if 'genprogs_post' in resultprofile:
	genprogs_post = resultprofile['genprogs_post']
if 'genprogs' in resultprofile:
	genprogs = resultprofile['genprogs']
genprogs = f"{genprogs_pre} {genprogs} {genprogs_post}"
shutil.copy('/safeboot/enroll.conf', ephemeral_dir)
with open(f"{ephemeral_dir}/enroll.conf", 'a') as fenroll:
	fenroll.write(f"export GENPROGS=({genprogs})")

# and give attest-enroll trust-roots for validating EKcerts
os.environ['TPM_VENDORS'] = f"{db_common.enrollsvc_state}/tpm_vendors"

# Safeboot's 'attest-enroll' evolved when we were doing things differently, now
# it's more convoluted than we need it to be. Eg. it calls CHECKOUT and COMMIT
# callbacks to determine the directory to enroll in and to post-process it.
# - our CHECKOUT hook reads $EPHEMERAL_ENROLL (which we set from
#   'ephemeral_dir' earlier in this file) and writes it to stdout.
# - our COMMIT hook does nothing
# - stdout/stderr are redirected to PIPEs that are then discarded. (This tool
#   is extremely noisy.) If debugging, you can uncomment the calls that send
#   the command's stdout/stderr to our own stderr. Don't forget however that we
#   can't send anything to stdout (except at the very end, when we write JSON
#   to stdout for our caller to pick up).
# We do the post-processing ourselves, from the ephemeral_dir, once
# 'attest-enroll' is done.
c = subprocess.run(
	[ '/safeboot/sbin/attest-enroll',
		'-C', f"{ephemeral_dir}/enroll.conf",
		'-V', 'CHECKOUT=/hcp/enrollsvc/cb_checkout.sh',
		'-V', 'COMMIT=/hcp/enrollsvc/cb_commit.sh',
		'-I', f"{path_ekpub}",
		f"{hostname}" ],
	cwd = '/safeboot',
	stdout = subprocess.PIPE,
	stderr = subprocess.PIPE,
	text = True)
if c.returncode != 0:
	# print(c.stdout, file = sys.stderr)
	# print(c.stderr, file = sys.stderr)
	bail(f"safeboot 'attest-enroll' failed: {c.returncode}")

# Enrollment performed, so assets are in 'ephemeral_dir'. Now we need to add it
# to the git-repo.

# ek.pub may not have existed prior to attest-enroll (if the client passes a
# different form, this form gets derived), so we hash it here. NB, db_common
# provides much of the hash/path handling for the git repo, we just calculate
# our own "halfhash" for logging and commit messages.
ekpubhash = hashlib.sha256(open(f"{ephemeral_dir}/ek.pub", 'rb').read()).hexdigest()
halfhash = ekpubhash[:16]

# Change working directory to the git repo
os.chdir(db_common.repo_path)

# Calculate paths to use in the DB for this ekpubhash
fpath = db_common.fpath(ekpubhash)
fpath_base = db_common.fpath_base(ekpubhash)
fpath_parent = db_common.fpath_parent(ekpubhash)

# The critical section begins
db_common.repo_lock()

# From here on in, we should not allow any error to prevent us from unlocking. Of course,
# issuing a "kill -9" or wrenching a live motherboard out of its chassis are not easily
# coded for, but we should at least control what we can.
caught = None
try:
	# Create the TPM's path in the DB or fail if it already exists
	if os.path.isdir(fpath):
		raise HcpErrorTPMalreadyEnrolled(f"existing ekpub: {halfhash}")
	os.makedirs(fpath_parent, exist_ok = True)
	# Copy all the generated assets (from attest-enroll)
	shutil.copytree(ephemeral_dir, fpath)
	# Add the hostname-to-ekpub entry to hn2ek.
	db_common.hn2ek_xadd(hostname, ekpubhash)
	# Write the 'ekpubhash' file
	open(f"{fpath}/ekpubhash", 'w').write(f"{ekpubhash}")
	# Store the client's requested profile
	open(f"{fpath}/clientprofile", 'w').write(f"{clientjson}")
	# Close the transaction
	run_git_cmd(['add', '.'])
	run_git_cmd(['commit', '-m', f"map {halfhash} to {hostname}"])
except Exception as e:
	caught = e
	log(f"Failed: enrollment DB 'add': {caught}")
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
# transaction. This gets returned to the client.
result = {
	'returncode': 0,
	'hostname': hostname,
	'ekpubhash': ekpubhash,
	'profile': clientdata
}
print(json.dumps(result, sort_keys = True))
