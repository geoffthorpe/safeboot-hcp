source /hcp/common/hcp.sh

# We pull the 'enrollsvc' config once and then interrogate it locally.
export HCP_ENROLLSVC_JSON=$(hcp_config_extract ".enrollsvc")
export HCP_ENROLLSVC_STATE=$(echo "$HCP_ENROLLSVC_JSON" | jq -r ".state")
export HCP_ENROLLSVC_GLOBAL_INIT=$(echo "$HCP_ENROLLSVC_JSON" | jq -r ".setup[0].touchfile")
export HCP_ENROLLSVC_LOCAL_INIT=$(echo "$HCP_ENROLLSVC_JSON" | jq -r ".setup[1].touchfile")
export HCP_ENROLLSVC_REALM=$(echo "$HCP_ENROLLSVC_JSON" | jq -r ".realm")
export HCP_ENROLLSVC_USER_DB=$(echo "$HCP_ENROLLSVC_JSON" | jq -r ".dbuser.id")
export HCP_ENROLLSVC_USER_DB_HANDLE=$(echo "$HCP_ENROLLSVC_JSON" | jq -r ".dbuser.handle")
export HCP_ENROLLSVC_USER_FLASK=$(echo "$HCP_ENROLLSVC_JSON" | jq -r ".webuser.id")
export HCP_ENROLLSVC_USER_FLASK_HANDLE=$(echo "$HCP_ENROLLSVC_JSON" | jq -r ".webuser.handle")
export HCP_ENROLLSVC_POLICYURL=$(echo "$HCP_ENROLLSVC_JSON" | jq -r ".policyurl")
export HCP_ENROLLSVC_VENDORS=$(echo "$HCP_ENROLLSVC_JSON" | jq -r ".tpm_vendors")

export HCP_DB_DIR=$HCP_ENROLLSVC_STATE/db

# Post-setup, includers of common.sh will be expecting the settings that setup
# produced to 'env';
if [[ -f "$HCP_ENROLLSVC_STATE/env" ]]; then
	source "$HCP_ENROLLSVC_STATE/env"
fi

# This function gets called by setup, which is the moment when we need to write
# a handle file which pins down the uid of the non-root accounts forever.
# (Well, the 'flask' user could probably vary over time because it's stateless,
# but certainly the 'emgmtdb' user needs to own most of the persistent data, so
# we can't have it changing around across reboots/upgrades.) We also have to call
# these during service startup too, for reasons explained in hcp.sh (where these
# functions are implemented). So we just make these calls whenever this file is sourced,
# and rely on it being harmless when the accounts already exist or when we're not
# running as root.

function do_enrollsvc_uid_setup {
	role_account_uid_file \
		$HCP_ENROLLSVC_USER_FLASK  \
		$HCP_ENROLLSVC_USER_FLASK_HANDLE  \
		"Flask User,,,,"
	role_account_uid_file \
		$HCP_ENROLLSVC_USER_DB \
		$HCP_ENROLLSVC_USER_DB_HANDLE \
		"EnrollDB User,,,,"
}

function expect_root {
	if [[ $WHOAMI != "root" ]]; then
		echo "Error, running as \"$WHOAMI\" rather than \"root\"" >&2
		exit 1
	fi
}

function expect_db_user {
	if [[ $WHOAMI != "$HCP_ENROLLSVC_USER_DB" ]]; then
		echo "Error, running as \"$WHOAMI\" rather than \"$HCP_ENROLLSVC_USER_DB\"" >&2
		exit 1
	fi
}

function expect_flask_user {
	if [[ $WHOAMI != "$HCP_ENROLLSVC_USER_FLASK" ]]; then
		echo "Error, running as \"$WHOAMI\" rather than \"$HCP_ENROLLSVC_USER_FLASK\"" >&2
		exit 1
	fi
}

function drop_privs_db {
	exec su -c "$*" - $HCP_ENROLLSVC_USER_DB
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

# Variables concerning the enrolldb
REPO_NAME=enrolldb.git
REPO_PATH=$HCP_DB_DIR/$REPO_NAME
REPO_LOCKPATH=$HCP_DB_DIR/lock-$REPO_NAME
EK_BASENAME=ekpubhash
EK_PATH=$REPO_PATH/$EK_BASENAME

# Variables concerning the HN2EK reverse-mapping file
HN2EK_BASENAME=hn2ek
HN2EK_PATH=$REPO_PATH/$HN2EK_BASENAME

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
