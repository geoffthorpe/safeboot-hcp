source /hcp/common/hcp.sh

function expect_root {
	if [[ `whoami` != "root" ]]; then
		echo "Error, running as \"`whoami`\" rather than \"root\"" >&2
		exit 1
	fi
}

# The root-written environment is stored here
export ENROLLSVC_ENV=/etc/environment.enrollsvc

# A note about security. We priv-sep the flask app (that implements the URL
# handlers for the management interface) from the enrollment code
# (asset-generation and DB manipulation). We run them both as distinct,
# non-root accounts. The flask handlers invoke the enrollment functions via a
# curated sudo configuration. A critical requirement is that there be no way
# for the caller (flask) to be able to influence the environment of the callee
# (enrollment). As such, we want to avoid whitelisting and other
# environment-forwarding mechanisms, as they represent potential attack vectors
# (e.g. if a flask handler is compromised).
#
# We can't solve this by baking all configuration into the container image
# (/etc/environment), because we want general-purpose Enrollment Service images
# that isn't configuration-specific, and we also want images to be (able to be)
# built and deployed from behind a CI pipeline, unaware of their intended
# usage.
#
# So, here's what we do;
# - "docker run" invocations always run, initially, as root within their
#   respective containers, before dropping privs to db_user (one-time init of
#   the database) or flask_user (to start the management interface). I.e. no
#   use of "--user", "sudo", or "su" in the "docker run" command-line.
# - We only ever drop privs, we never escalate to root.
# - Instance configuration is passed in as "--env" arguments to "docker run".
# - This common.sh file detects when it is running as root and will _write_
#   /etc/environment in that case.
# - All non-root environments pick up this uncontaminated /etc/environment;
#   - when we drop privs, and
#   - when a call is made across a sudo boundary.
# - No whitelisting or other environment carry-over.
#
# NB: we support composite container images (like 'caboodle') that not only
# contain the implementation of multiple services but can also run multiple
# such instances within the same container instance. As a consequence, if
# multiple distinct enrollsvc instances are run (or instances of another,
# similar service that uses similar "flask_user"/"db_user" accounts), they will
# collide! As such, we rely on environment variables to tell us the actual
# account names to use for those two system roles.
#
# Further, our service may be started and stopped within a single long-running
# environment, and/or it may be a container that gets torn down and started up.
# In the former case, accounts within the OS will persist across invocations,
# whereas the latter will disappear each time a new container is created. This
# is independently true for the two co-services (mgmt and repl). This is why
# common.sh always tries to create these system accounts on the fly, and checks
# whether failure is because of a race.
#
# Needless to say, the environment passed in when a service instance is first
# configured must be the same each and every other time that the service is
# started!

if [[ `whoami` != "root" ]]; then

	# We're not root, so we source the env-vars that root put there.
	if [[ -z "$HCP_ENVIRONMENT_SET" ]]; then
		echo "Running in reduced non-root environment (sudo probably)." >&2
		source $ENROLLSVC_ENV
	fi

else

if [[ -z $HCP_ENVIRONMENT_SET && -f $ENROLLSVC_ENV ]]; then
	echo "Running in root environment and sourcing existing config" >&2
	source $ENROLLSVC_ENV
fi

# If we're root, this environment should already be known
if [[ ! -d $HCP_ENROLLSVC_STATE ]]; then
	echo "Error, HCP_ENROLLSVC_STATE ($HCP_ENROLLSVC_STATE) doesn't exist" >&2
	exit 1
fi
if [[ -z $HCP_ENROLLSVC_USER_FLASK || -z $HCP_ENROLLSVC_USER_DB ]]; then
	echo "Error, HCP_ENROLLSVC_USER_{FLASK,DB} must be set" >&2
	exit 1
fi

# All the DB_USER-owned stuff goes into this sub-directory
export HCP_DB_DIR=$HCP_ENROLLSVC_STATE/db

role_account_uid_file \
	$HCP_ENROLLSVC_USER_FLASK  \
	$HCP_ENROLLSVC_STATE/uid_flask_user \
	"Flask User,,,,"
role_account_uid_file \
	$HCP_ENROLLSVC_USER_DB \
	$HCP_ENROLLSVC_STATE/uid_db_user \
	"EnrollDB User,,,,"

# Generate env file if it doesn't exist yet
if [[ ! -f $ENROLLSVC_ENV ]]; then
	echo "Generating '$ENROLLSVC_ENV'"
	touch $ENROLLSVC_ENV
	chmod 644 $ENROLLSVC_ENV
	echo "# HCP enrollsvc settings" > $ENROLLSVC_ENV
	export_hcp_env >> $ENROLLSVC_ENV
	# We also set some stuff that isn't "HCP_"-prefixed, as consumed by
	# safeboot scripts.
	export SIGNING_KEY_DIR=/home/$HCP_ENROLLSVC_USER_DB/enrollsigner
	export SIGNING_KEY_PUB=$SIGNING_KEY_DIR/key.pem
	export SIGNING_KEY_PRIV=$SIGNING_KEY_DIR/key.priv
	export GENCERT_CA_DIR=/home/$HCP_ENROLLSVC_USER_DB/enrollcertissuer
	export GENCERT_CA_CERT=$GENCERT_CA_DIR/CA.cert
	export GENCERT_CA_PRIV=$GENCERT_CA_DIR/CA.pem
	cat >> $ENROLLSVC_ENV <<EOF
export SIGNING_KEY_DIR=$SIGNING_KEY_DIR
export SIGNING_KEY_PUB=$SIGNING_KEY_PUB
export SIGNING_KEY_PRIV=$SIGNING_KEY_PRIV
export GENCERT_CA_DIR=$GENCERT_CA_DIR
export GENCERT_CA_CERT=$GENCERT_CA_CERT
export GENCERT_CA_PRIV=$GENCERT_CA_PRIV
EOF
	echo "export HCP_ENVIRONMENT_SET=1" >> $ENROLLSVC_ENV
fi

# Copy creds to the home dir if we have them and they aren't copied yet
if [[ -n $HCP_ENROLLSVC_SIGNER && -d "$HCP_ENROLLSVC_SIGNER" &&
		! -d "$SIGNING_KEY_DIR" ]]; then
	echo "Copying asset-signing creds to '$SIGNING_KEY_DIR'"
	cp -r $HCP_ENROLLSVC_SIGNER $SIGNING_KEY_DIR
	chown -R $HCP_ENROLLSVC_USER_DB $SIGNING_KEY_DIR
fi
if [[ -n $HCP_ENROLLSVC_CERTISSUER && -d "$HCP_ENROLLSVC_CERTISSUER" &&
		! -d "$GENCERT_CA_DIR" ]]; then
	echo "Copying cert-issuer creds to '$GENCERT_CA_DIR'"
	cp -r $HCP_ENROLLSVC_CERTISSUER $GENCERT_CA_DIR
	chown -R $HCP_ENROLLSVC_USER_DB $GENCERT_CA_DIR
fi

# Handle global state initialization, part A
if [[ ! -f $HCP_ENROLLSVC_STATE/initialized ]]; then

	echo "Initializing enrollsvc state"

	echo " - generating '$HCP_ENROLLSVC_STATE/sudoers'"
	cat > "$HCP_ENROLLSVC_STATE/sudoers" <<EOF
# sudo rules for enrollsvc-mgmt" > /etc/sudoers.d/hcp
Cmnd_Alias HCP = /hcp/enrollsvc/op_add.sh,/hcp/enrollsvc/op_delete.sh,/hcp/enrollsvc/op_find.sh,/hcp/enrollsvc/op_query.sh
Defaults !lecture
Defaults !authenticate
$HCP_ENROLLSVC_USER_FLASK ALL = ($HCP_ENROLLSVC_USER_DB) HCP
EOF

	echo " - generating '$HCP_ENROLLSVC_STATE/safeboot-enroll.conf'"
	cat > $HCP_ENROLLSVC_STATE/safeboot-enroll.conf <<EOF
# Autogenerated by enrollsvc/run_mgmt.sh
export GENCERT_CA_PRIV=$GENCERT_CA_PRIV
export GENCERT_CA_CERT=$GENCERT_CA_CERT
export DIAGNOSTICS=$DIAGNOSTICS
POLICIES[cert-hxtool]=pcr11
POLICIES[rootfskey]=pcr11
EOF

	echo " - generating DB_USER-owned data in '$HCP_DB_DIR'"
	mkdir $HCP_DB_DIR
	chown $HCP_ENROLLSVC_USER_DB $HCP_DB_DIR

	echo " - generating '$HCP_ENROLLSVC_STATE/tpm_vendors'"
	mkdir $HCP_ENROLLSVC_STATE/tpm_vendors
	if [[ -d $HCP_ENROLLSVC_VENDORS ]]; then
		TRUST_OUT="$HCP_ENROLLSVC_STATE/tpm_vendors" \
		TRUST_IN="$HCP_ENROLLSVC_VENDORS" \
		/hcp/enrollsvc/vendors_install.sh
	else
		echo "   - No vendors founds ($HCP_ENROLLSVC_VENDORS)"
	fi
fi

# Steps that may need running on each container launch (not just first-time
# initialization)
if ! ln -s "$HCP_ENROLLSVC_STATE/sudoers" /etc/sudoers.d/hcp > /dev/null 2>&1 && \
		[[ ! -h /etc/sudoers.d/hcp ]]; then
	echo "Error, couldn't create symlink '/etc/sudoers.d/hcp'" >&2
	exit 1
fi
if ! ln -s "$HCP_ENROLLSVC_STATE/safeboot-enroll.conf" \
			/safeboot/enroll.conf > /dev/null 2>&1 &&
		[[ ! -h /safeboot/enroll.conf ]]; then
	echo "Error, couldn't create symlink '/safeboot/enroll.conf'" >&2
	exit 1
fi

# Functions that are needed by root environments. (Including the "part B" code
# just below, which needs to know how to drop_privs_db.)
function drop_privs_db {
	# The only thing we need to whitelist is ENROLLSVC_IN_SETUP, to
	# suppress our checks for the existence of a directory at $(EK_PATH).
	# I.e.  run_repl.sh uses this when polling to wait for the database to
	# be initialized (without which our check would cause it to exit), and
	# run_mgmt.sh uses it when making the same check and when subsequently
	# initializing the database.
	exec su --whitelist-environment ENROLLSVC_IN_SETUP -c "$*" - $HCP_ENROLLSVC_USER_DB
}

# Handle first-time initialization, part B
if [[ ! -f "$HCP_ENROLLSVC_STATE/initialized" ]]; then
	echo "   - initializing repo"
	(ENROLLSVC_IN_SETUP=1 drop_privs_db /hcp/enrollsvc/init_repo.sh)
	touch "$HCP_ENROLLSVC_STATE/initialized"
	echo "State now initialized"
fi

fi # end of if(whoami==root)

# The remaining code is processed by all includers, in all contexts.

function expect_db_user {
	if [[ `whoami` != "$HCP_ENROLLSVC_USER_DB" ]]; then
		echo "Error, running as \"`whoami`\" rather than \"$HCP_ENROLLSVC_USER_DB\"" >&2
		exit 1
	fi
}

function expect_flask_user {
	if [[ `whoami` != "$HCP_ENROLLSVC_USER_FLASK" ]]; then
		echo "Error, running as \"`whoami`\" rather than \"$HCP_ENROLLSVC_USER_FLASK\"" >&2
		exit 1
	fi
}

if [[ -z "$DIAGNOSTICS" ]]; then
	export DIAGNOSTICS="false"
fi

function repo_cmd_lock {
	[[ -f $REPO_LOCKPATH ]] && echo "Warning, lockfile contention" >&2
	lockfile -1 -r 5 -l 30 -s 5 $REPO_LOCKPATH
}

function repo_cmd_unlock {
	rm -f $REPO_LOCKPATH
}

# The remaining functions are used for navigating and manipulating the
# enrollment database.
#
# TODO: we could do much better than the HN2EK stuff. The enrollmentdb (as
# managed in git) inherently maps TPMs (a hash of their 'ekpub') to their
# corresponding hosts (hostname and the assets enrolled for it). The HN2EK
# mechanism sits outside that, using a single file to provide a reverse
# mapping. Reverse-mapping isn't a common requirement and needn't be
# performant. Also, adding and deleting to/from the enrolldb database involves
# stacks of scripts, lots of crypto and I/O, and operations on a git repo.
# Updating the HN2EK file should be small in comparison.
#
# HOWEVER, those add/delete operations on the enrolldb are constant-time,
# however heavy they might be, whereas the updates to the HN2EK file are at
# least linear with fleet size, so it's conceivable that it needs a smarter
# approach if very large fleet sizes cause the HN2EK overheads to dominate.
# copies of the table inside the critical section).


# The HN2EK reverse-mapping table is pretty simple. Each line of this file is a
# space-separated 2-tuple of;
# - the reversed hostname (per 'rev')
# - the ekpubhash (truncated to 32 characters if appropriate, i.e. to match the
#   name of the per-TPM sub-sub-sub-drectory in the ekpubhash/ directory tree).

# Variables concerning the enrolldb
REPO_NAME=enrolldb.git
REPO_PATH=$HCP_DB_DIR/$REPO_NAME
REPO_LOCKPATH=$HCP_DB_DIR/lock-$REPO_NAME
EK_BASENAME=ekpubhash
EK_PATH=$REPO_PATH/$EK_BASENAME

# Variables concerning the HN2EK reverse-mapping file
HN2EK_BASENAME=hn2ek
HN2EK_PATH=$REPO_PATH/$HN2EK_BASENAME

# EK_PATH must point to the 'ekpubhash' directory (in the "enrolldb.git"
# repo/clone), unless (of course) we are being sourced by the script that is
# creating the repo.
if [[ -z "$EK_PATH" || ! -d "$EK_PATH" ]]; then
	if [[ -z "$ENROLLSVC_IN_SETUP" ]]; then
		echo "Error, EK_PATH must point to the ekpubhash lookup tree" >&2
		exit 1
	fi
fi

# ekpubhash must consist only of lower-case hex, and be at least 16 characters
# long (8 bytes)
function check_ekpubhash {
	(echo "$1" | egrep -e "^[0-9a-f]{16,}$" > /dev/null 2>&1) ||
		(echo "Error, malformed ekpubhash" >&2 && exit 1) || exit 1
}

# the prefix version can be any length (including empty)
function check_ekpubhash_prefix {
	(echo "$1" | egrep -e "^[0-9a-f]*$" > /dev/null 2>&1) ||
		(echo "Error, malformed ekpubhash" >&2 && exit 1) || exit 1
}

# hostname must consist only of alphanumerics, periods ("."), hyphens ("-"),
# and underscores ("_"). TODO: our code actually allows empty hostnames, which
# is why the "_suffix" version doesn't do anything special. (The _suffix
# version certainly _should_ accept the empty case, because it's a suffix match
# for a query), but we should probably require hostnames to be non-empty, and
# probably satisfy some other sane-hostname constraints.
function check_hostname {
	(echo "$1" | egrep -e "^[0-9a-zA-Z._-]*$" > /dev/null 2>&1) ||
		(echo "Error, malformed hostname" >&2 && exit 1) || exit 1
}
function check_hostname_suffix {
	check_hostname $1
}

# We use a 3-ply directory hierarchy for storing per-TPM state, indexed by the
# "ekpubhash" of that TPM (or more accurately, the hexidecimal string
# representation of the ekpubhash in text form - 4 bits per ASCII character).
# The first ply uses the first 2 hex characters as a directory name, for a
# split of 256. The second ply uses the first 6 characters as a directory name,
# meaning 4 new characters of uniqueness for a further split of 65536,
# resulting in a total split of ~16 million. The last ply uses the first 32
# characters of the ekpubhash, with a working assumption that this (128-bits)
# is enough to establish TPM uniqueness, and no collision-handling is employed
# beyond that. That 3rd-ply (per-TPM) directory contains individual files for
# each attribute to be associated with the TPM, including 'ekpubhash' itself
# (full-length), and 'hostname'.

# Given an ekpubhash ($1), figure out the corresponding 3-ply of directories.
# Outputs;
#   PLY1, PLY2, PLY3: directory names
#   FPATH: full path
function ply_path_add {
	PLY1=`echo $1 | cut -c 1,2`
	PLY2=`echo $1 | cut -c 1-6`
	PLY3=`echo $1 | cut -c 1-32`
	FPATH="$EK_PATH/$PLY1/$PLY2/$PLY3"
}

# Given an ekpubhash prefix ($1), figure out the wildcard to match on all the
# matching per-TPM directories. (If using "ls", don't forget to use the "-d"
# switch!)
# Outputs;
#   FPATH: full path with wildcard pattern
function ply_path_get {
	len=${#1}
	if [[ $len -lt 2 ]]; then
		FPATH="$EK_PATH/$1*/*/*"
	else
		PLY1=`echo $1 | cut -c 1,2`
		if [[ $len -lt 6 ]]; then
			FPATH="$EK_PATH/$PLY1/$1*/*"
		else
			PLY2=`echo $1 | cut -c 1-6`
			if [[ $len -lt 32 ]]; then
				FPATH="$EK_PATH/$PLY1/$PLY2/$1*"
			else
				PLY3=`echo $1 | cut -c 1-32`
				FPATH="$EK_PATH/$PLY1/$PLY2/$PLY3"
			fi
		fi
	fi
}
