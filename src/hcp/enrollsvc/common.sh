source /hcp/common/hcp.sh

# We pull the 'enrollsvc' config once and then interrogate it locally.
export HCP_ENROLLSVC_JSON=$(hcp_config_extract ".enrollsvc")
export HCP_ENROLLSVC_STATE=$(echo "$HCP_ENROLLSVC_JSON" | jq -r ".state")
export HCP_ENROLLSVC_GLOBAL_INIT=$(echo "$HCP_ENROLLSVC_JSON" | jq -r ".setup[0].touchfile")
export HCP_ENROLLSVC_LOCAL_INIT=$(echo "$HCP_ENROLLSVC_JSON" | jq -r ".setup[1].touchfile")
export HCP_ENROLLSVC_REALM=$(echo "$HCP_ENROLLSVC_JSON" | jq -r ".realm")
export HCP_ENROLLSVC_USER_DB=$(echo "$HCP_ENROLLSVC_JSON" | jq -r ".dbuser // empty")
if [[ -z $HCP_ENROLLSVC_USER_DB ]]; then
	export HCP_ENROLLSVC_USER_DB=emgmtdb
fi
export HCP_ENROLLSVC_USER_FLASK=$(echo "$HCP_ENROLLSVC_JSON" | jq -r ".webuser // empty")
if [[ -z $HCP_ENROLLSVC_USER_FLASK ]]; then
	export HCP_ENROLLSVC_USER_FLASK=emgmtflask
fi
export HCP_ENROLLSVC_POLICYURL=$(echo "$HCP_ENROLLSVC_JSON" | jq -r ".policyurl")
export HCP_ENROLLSVC_VENDORS=$(echo "$HCP_ENROLLSVC_JSON" | jq -r ".tpm_vendors")

export HCP_DB_DIR=$HCP_ENROLLSVC_STATE/db

if [[ $WHOAMI == "root" ]]; then
	hcp_config_user_init $HCP_ENROLLSVC_USER_DB
	hcp_config_user_init $HCP_ENROLLSVC_USER_FLASK
fi

# Post-setup, includers of common.sh will be expecting the settings that setup
# produced to 'env';
if [[ -f "$HCP_ENROLLSVC_STATE/env" ]]; then
	source "$HCP_ENROLLSVC_STATE/env"
fi

# Although the following is a "local" setup issue (because it gets lost and
# needs repeating whenever the rootfs is reset, eg. after an image upgrade), we
# need to do it even before "global" setup occurs, which usually precedes local
# setup. Background: we have constraints to support older Debian versions whose
# 'git' packages assume "master" as a default branch name and don't honor
# attempts to override that via the "defaultBranch" configuration setting. More
# recent distro versions may change their defaults (e.g. to "main"), but we
# know that such versions will also honor this configuration setting, whereas
# the older versions won't. In the interests of maximum interoperability we go
# with "master", whilst acknowledging that this goes against coding guidelines
# in many environments.  If you have no such legacy distro constraints and wish
# to (or must) adhere to revised naming conventions, please alter this setting
# accordingly.
git config --global init.defaultBranch master

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
