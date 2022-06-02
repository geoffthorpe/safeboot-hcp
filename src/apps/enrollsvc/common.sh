. /hcp/common/hcp.sh

set -e

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
# (not configuration-specific), and we want images to be built and deployed
# from behind a CI pipeline, not by prod hosts and operators.
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
# NB: because the user accounts (db_user and flask_user) are created by
# Dockerfile, those values _are_ baked into the container images and get
# propogated into the initial (root) environment by "ENV" commands in the
# Dockerfile. HCP_ENROLLSVC_STATE, on the other hand, is specified at "docker
# run" time. This file treats them all the same way, but it's worth knowing.

if [[ `whoami` != "root" ]]; then
	if [[ -z "$HCP_ENVIRONMENT_SET" ]]; then
		echo "Running in reduced non-root environment (sudo probably)." >&2
		cat /etc/environment >&2
		source /etc/environment
	fi
fi

if [[ ! -d "/home/db_user" ]]; then
	echo "Error, 'db_user' account missing or misconfigured" >&2
	exit 1
fi
if [[ ! -d "/home/flask_user" ]]; then
	echo "Error, 'flask_user' account missing or misconfigured" >&2
	exit 1
fi

if [[ ! -d "/safeboot/sbin" ]]; then
	echo "Error, /safeboot/sbin is not present" >&2
	exit 1
fi
export PATH=$PATH:/safeboot/sbin
echo "Adding /safeboot/sbin to PATH" >&2

if [[ -d "/install/bin" ]]; then
	export PATH=$PATH:/install/bin
	echo "Adding /install/sbin to PATH" >&2
fi

if [[ -d "/install/lib" ]]; then
	export LD_LIBRARY_PATH=/install/lib:$LD_LIBRARY_PATH
	echo "Adding /install/lib to LD_LIBRARY_PATH" >&2
	if [[ -d /install/lib/python3/dist-packages ]]; then
		export PYTHONPATH=/install/lib/python3/dist-packages:$PYTHONPATH
		echo "Adding /install/lib/python3/dist-packages to PYTHONPATH" >&2
	fi
fi

if [[ `whoami` == "root" ]]; then
	# We're root, so we write the env-vars we got (from docker-run) to
	# /etc/environment so that non-root paths through common.sh source
	# those known-good values.
	touch /etc/environment
	chmod 644 /etc/environment
	echo "# HCP enrollsvc settings, put here so that non-root environments" >> /etc/environment
	echo "# always get known-good values, especially via sudo!" >> /etc/environment
	export_hcp_env >> /etc/environment
	echo "export HCP_ENVIRONMENT_SET=1" >> /etc/environment
fi

# Derive more configuration using these constants
REPO_NAME=enrolldb.git
EK_BASENAME=ekpubhash
REPO_PATH=$HCP_ENROLLSVC_STATE/$REPO_NAME
EK_PATH=$REPO_PATH/$EK_BASENAME
REPO_LOCKPATH=$HCP_ENROLLSVC_STATE/lock-$REPO_NAME

# Basic functions

function expect_root {
	if [[ `whoami` != "root" ]]; then
		echo "Error, running as \"`whoami`\" rather than \"root\"" >&2
		exit 1
	fi
}

function expect_db_user {
	if [[ `whoami` != "db_user" ]]; then
		echo "Error, running as \"`whoami`\" rather than \"db_user\"" >&2
		exit 1
	fi
}

function expect_flask_user {
	if [[ `whoami` != "flask_user" ]]; then
		echo "Error, running as \"`whoami`\" rather than \"flask_user\"" >&2
		exit 1
	fi
}

function drop_privs_db {
	# The only thing we need to whitelist is DB_IN_SETUP, to suppress our
	# checks for the existence of a directory at $(EK_PATH). I.e.
	# run_repl.sh uses this when polling to wait for the database to be
	# initialized (without which our check would cause it to exit), and
	# run_mgmt.sh uses it when making the same check and when subsequently
	# initializing the database.
	exec su --whitelist-environment DB_IN_SETUP -c "$*" - db_user
}

function drop_privs_flask {
	exec su -c "$*" - flask_user
}

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

# The initially-empty file
HN2EK_BASENAME=hn2ek
HN2EK_PATH=$REPO_PATH/$HN2EK_BASENAME

# The following definitions are for the git-based enrolldb.

# EK_PATH must point to the 'ekpubhash' directory (in the "enrolldb.git"
# repo/clone), unless (of course) we are being sourced by the script that is
# creating the repo.
if [[ -z "$EK_PATH" || ! -d "$EK_PATH" ]]; then
	if [[ -z "$DB_IN_SETUP" ]]; then
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
