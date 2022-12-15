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

sys.path.insert(1, '/hcp/common')

from hcp_common import log, current_tracefile, http2exit, \
	env_get_dir, env_get_file, hcp_config_extract

sys.path.insert(1, '/hcp/xtra')

from HcpHostname import valid_hostname, dc_hostname, pop_hostname, pop_domain
from HcpRecursiveUnion import union
import HcpJsonExpander

sys.path.insert(1, '/hcp/enrollsvc')
import db_common
bail = db_common.bail
git_commit = db_common.git_commit
git_reset = db_common.git_reset

# IMPORTANT: this file must send any miscellaneous output to stderr _only_.
# This process is launched (by mgmt_sudo.sh) behind a 'sudo' call from the
# web-app, which is expecting JSON output to show up on stdout when we exit
# (unless we exit non-zero). Anything else that goes to stdout will likely
# corrupt the JSON.

class HcpErrorTPMalreadyEnrolled(Exception):
	pass
class HcpErrorTPMnotEnrolled(Exception):
	pass

# Usage: either
#     db_add.py add <path-to-ekpub> <hostname> <clientjson>
# or
#     db_add.py reenroll <ekpubhash>

if len(sys.argv) < 2 or (sys.argv[1] != 'add' and
			sys.argv[1] != 'reenroll'):
	bail("First argument must be 'add' or 'reenroll")

cmdname = sys.argv[1]
log(f"db_add: starting '{cmdname}'")
z = f"db_{cmdname}"

# We expect these env-vars to point to things
signing_key_dir = env_get_dir('SIGNING_KEY_DIR')
signing_key_pub = env_get_file('SIGNING_KEY_PUB')
signing_key_priv = env_get_file('SIGNING_KEY_PRIV')
gencert_ca_dir = env_get_dir('GENCERT_CA_DIR')
gencert_ca_cert = env_get_file('GENCERT_CA_CERT')
gencert_ca_priv = env_get_file('GENCERT_CA_PRIV')

# Make sure attest-enroll prefers HCP's genprogs
genprogspath = '/hcp/enrollsvc/genprogs'
if 'PATH' in os.environ:
	genprogspath=f"{genprogspath}:{os.environ['PATH']}"
os.environ['PATH']=genprogspath

# Enroll in a temp directory that gets automatically cleaned up
ephemeral_dir_obj = TemporaryDirectory()
ephemeral_dir = ephemeral_dir_obj.name
os.environ['EPHEMERAL_ENROLL'] = ephemeral_dir
log(f"{z}: ephemeral_dir={ephemeral_dir}")

# Load the server's config and extract the "preclient" and "postclient"
# profiles.
serverprofile = hcp_config_extract('.enrollsvc.db_add', must_exist = True)
log(f"{z}: serverprofile={serverprofile}")
serverprofile_pre = serverprofile.pop('preclient', {})
serverprofile_post = serverprofile.pop('postclient', {})

# We also need to pull the policy URL (if any) from our JSON input. We'll pump
# this into the environment so that any child processes (eg. genprogs) that
# expect it get it.
policy_url = hcp_config_extract('.enrollsvc.policy_url', or_default = True)
if policy_url:
	os.environ['HCP_ENROLLSVC_POLICY'] = policy_url
else:
	if 'HCP_ENROLLSVC_POLICY' in os.environ:
		os.environ.pop('HCP_ENROLLSVC_POLICY')

# Initialization that differs between enroll/reenroll
if cmdname == 'add':
	if len(sys.argv) != 5:
		bail(f"{z}: wrong number of arguments: {len(sys.argv)}")
	log(f"{z}: args [{sys.argv[2]},{sys.argv[3]},{sys.argv[4]}]")

	path_ekpub = sys.argv[2]
	if not os.path.exists(path_ekpub):
		bail(f"No file at ekpub path: {path_ekpub}")

	hostname = sys.argv[3]
	valid_hostname(hostname)

	clientjson = sys.argv[4]
	if len(clientjson) == 0:
		bail(f"Empty JSON")
else: # cmdname == 'reenroll'
	if len(sys.argv) != 3:
		bail(f"{z}: wrong number of arguments: {len(sys.argv)}")
	log(f"{z}: args [{sys.argv[2]}]")

	clientjson = sys.argv[2]
	log(f"{z}: using clientjson={clientjson}")
	if len(clientjson) == 0:
		bail(f"Empty JSON")
	clientdata = json.loads(clientjson)
	log(f"{z}: clientdata={clientdata}")
	ekpubhash = clientdata['ekpubhash']
	log(f"{z}: ekpubhash={ekpubhash}")
	db_common.valid_ekpubhash(ekpubhash)

	# 'enroll' has to figure out fpath after attest-enroll runs,
	# 'reenroll' has to figure it out long before that.
	fpath = db_common.fpath(ekpubhash)
	log(f"{z}: fpath={fpath}")
	check = open(f"{fpath}/ekpubhash", 'r').read().strip('\n')
	if ekpubhash != check:
		bail(f"{z}: fail, ekpubhash={ekpubhash}, check={check}")
	clientjson = open(f"{fpath}/clientprofile", 'r').read().strip('\n')
	hostname = open(f"{fpath}/hostname", 'r').read().strip('\n')
	log(f"{z}: found hostname={hostname}")
	path_ekpub = f"{fpath}/ek.pub"

# Now merge with the client. Basically this is a non-shallow merge, in which
# the client's (requested) profile is overlaid on the server's "preclient"
# profile, and then the server's "postclient" profile is overlaid on top of
# that.
clientdata = json.loads(clientjson)
log(f"{z}: clientdata={clientdata}")
resultprofile = union(union(serverprofile_pre, clientdata), serverprofile_post)
log(f"db_add: client-adjusted resultprofile={resultprofile}")

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
_id, _domain = pop_domain(hostname, domain)
if not _domain:
	_id = "unknown_id"
domain2dc = dc_hostname(domain)
xtra_env = {
	'__env': {
		'ENROLL_ID': _id,
		'ENROLL_HOSTNAME': hostname,
		'SIGNING_KEY_DIR': signing_key_dir,
		'SIGNING_KEY_PUB': signing_key_pub,
		'SIGNING_KEY_PRIV': signing_key_priv,
		'GENCERT_CA_DIR': gencert_ca_dir,
		'GENCERT_CA_CERT': gencert_ca_cert,
		'GENCERT_CA_PRIV': gencert_ca_priv,
		'ENROLL_HOSTNAME2DC': hostname2dc,
		'ENROLL_DOMAIN2DC': domain2dc
	}
}
resultprofile=union(resultprofile, xtra_env)
log(f"{z}: env-adjusted resultprofle={resultprofile}")

# Now we need to perform parameter-expansion
origenv = resultprofile.pop('__env', {})
resultprofile = HcpJsonExpander.process_obj(origenv, resultprofile, '.',
			varskey = None, fileskey = None)
resultprofile['__env'] = origenv
log(f"{z}: param-expanded resultprofle={resultprofile}")

# The only thing left to do to resultprofile is determine which genprogs to
# run, and the genprogs themselves don't need to know that, so export the
# resultprofile now so that safeboot and/or genprogs scripts can get at it.
os.environ['ENROLL_JSON'] = json.dumps(resultprofile)

# And we now deal with genprogs[_{pre,post}]
genprogs_pre = ""
genprogs_post = ""
genprogs = ""
if 'genprogs_pre' in resultprofile:
	genprogs_pre = resultprofile['genprogs_pre']
if 'genprogs_post' in resultprofile:
	genprogs_post = resultprofile['genprogs_post']
if 'genprogs' in resultprofile:
	genprogs = resultprofile['genprogs']
final_genprogs = f"{genprogs_pre} {genprogs} {genprogs_post}"
# NB: we keep the 'final_genprogs' variable as a space-separated string for the
# benefit of safeboot, which expects it. But the correspondingly-named field in
# the profile will be an array.
resultprofile['final_genprogs'] = final_genprogs.split(' ')

# The JSON profile is now fully curated. (The only thing left to do is generate
# the enroll.conf that safeboot's 'attest-enroll' requires, but that's only
# because it doesn't consume our profile.)
# So before doing that and performing the enrollment, send our profile to the
# policy-checker!
if policy_url:
	uuid = uuid4().urn
	os.environ['HCP_REQUEST_UID'] = uuid
	form_data = {
		'hookname': (None, "enrollsvc::add_request"),
		'request_uid': (None, uuid),
		'params': (None, json.dumps(resultprofile))
	}
	url = f"{policy_url}/run"
	log(f"{z}: sending policy request={form_data}")
	try:
		response = requests.post(url, files=form_data)
		log(f"{z}: policy response={response}")
		status = response.status_code
	except Exception as e:
		log(f"{z}: policy connection failed: {e}")
		status = 403
	if status != 200:
		log(f"policy-checker refused enrollment: {status}")
		sys.exit(http2exit(403))

# Prepare the enroll.conf that safeboot feeds on
shutil.copy('/install-safeboot/enroll.conf', ephemeral_dir)
log(f"db_add: adding GENPROGS=({final_genprogs})")
with open(f"{ephemeral_dir}/enroll.conf", 'a') as fenroll:
	fenroll.write(f"export GENPROGS=({final_genprogs})")

# and give attest-enroll trust-roots for validating EKcerts
log(f"db_add: setting TPM_VENDORS={db_common.enrollsvc_state}/tpm_vendors")
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
	[ '/install-safeboot/sbin/attest-enroll', '-v',
		'-C', f"{ephemeral_dir}/enroll.conf",
		'-V', 'CHECKOUT=/hcp/enrollsvc/cb_checkout.sh',
		'-V', 'COMMIT=/hcp/enrollsvc/cb_commit.sh',
		'-I', f"{path_ekpub}",
		f"{hostname}" ],
	cwd = '/install-safeboot',
	stdout = subprocess.PIPE,
	stderr = current_tracefile,
	text = True)
log(f"{z}: attest-enroll returned c={c}")
if c.returncode != 0:
	bail(f"{z}: safeboot 'attest-enroll' failed: {c.returncode}")

# Enrollment performed, so assets are in 'ephemeral_dir'. Now we need to add it
# to the git-repo.

# For 'add', ek.pub may have first been produced during attest-enroll (if
# the client passed us the EK in a different form, attest-enroll converts
# it), so in that case we hash it here. By dependency, the same is true of
# fpath.
if cmdname == 'add':
	ekpubhash = hashlib.sha256(open(f"{ephemeral_dir}/ek.pub",
				'rb').read()).hexdigest()
	fpath = db_common.fpath(ekpubhash)
	log(f"{z}: ekpubhash={ekpubhash}")
	log(f"{z}: fpath={fpath}")
halfhash = ekpubhash[:16]

# Change working directory to the git repo
os.chdir(db_common.repo_path)

# The critical section begins
log("{z}: critical section beginning")
db_common.repo_lock()

# From here on in, we should not allow any error to prevent us from unlocking. Of course,
# issuing a "kill -9" or wrenching a live motherboard out of its chassis are not easily
# coded for, but we should at least control what we can.
caught = None
try:
	if cmdname == 'add':
		# For 'add', the TPM must _not_ already be enrolled
		if os.path.isdir(fpath):
			raise HcpErrorTPMalreadyEnrolled(f"existing ekpub: {halfhash}")
		# Add the hostname-to-ekpub entry to hn2ek, it's new
		log("{z}: add hn2ek entry")
		db_common.hn2ek_xadd(hostname, ekpubhash)
	else: # cmdname == 'reenroll'
		# For 'reenroll', the TPM _must_ already be enrolled
		if not os.path.isdir(fpath):
			raise HcpErrorTPMnotEnrolled(f"unknown ekpub: {halfhash}")
		# Remove the existing tree. If anything goes wrong, the
		# exception handler's 'git reset --hard' will restore what was
		# removed. Also we hold the lock, so the tree-deletion never
		# gets committed to git, so it goes unseen, unreplicated, etc.
		shutil.rmtree(fpath)
	# Copy the ephemeral enrollment dir into place. I could have moved it
	# instead, but (a) TemporaryDirectory() garbage-collects the ephemeral
	# dir and I don't want any surprises from that, and (b) it could be
	# that umasks or sticky-bits or group-ids or mount options differ
	# between the ephemeral dir and the git repo, and because 'cp' creates
	# all the destination dirs and files, it would seem less prone to
	# oddity than 'mv'.
	log(f"{z}: move enrollment to DB at {fpath}")
	import glob
	shutil.copytree(ephemeral_dir, fpath)
	# Add 'ekpubhash' and 'clientprofile' files
	log("{z}: adding ekpubhash and clientprofile")
	open(f"{fpath}/ekpubhash", 'w').write(f"{ekpubhash}")
	open(f"{fpath}/clientprofile", 'w').write(f"{clientjson}")
	# Close the transaction
	git_commit(f"map {halfhash} to {hostname}")
except Exception as e:
	caught = e
	log(f"{z}: caught exception: {caught}")
	# recover the git repo before we release the lock
	try:
		git_reset()
	except Exception as e:
		log(f"{z}: rollback failed!! {e}")
		bail(f"CATASTROPHIC! DB stays locked for manual intervention")
	log("{z}: rollback complete")

# Remove the lock, then reraise any exception we intercepted
db_common.repo_unlock()
if caught:
	log(f"{z}: exception continuation: {caught}")
	raise caught
log("{z}: critical section complete")

# The point of this entire file: produce a JSON to stdout that confirms the
# transaction. This gets returned to the client.
result = {
	'returncode': 0,
	'hostname': hostname,
	'ekpubhash': ekpubhash,
	'profile': clientdata
}
print(json.dumps(result, sort_keys = True))
log("{z}: JSON output produced, exiting with code 201")
sys.exit(http2exit(201))
