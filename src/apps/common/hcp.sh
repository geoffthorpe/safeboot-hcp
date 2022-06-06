#!/bin/bash

# Adds safeboot's "sbin" to the PATH. If optional argument $1 is non-empty, we
# also source safeboot's "functions.sh"
function need_safeboot {
	if [[ ! -d "/safeboot/sbin" ]]; then
		echo "Error, /safeboot/sbin is not present" >&2
		return 1
	fi
	echo "Adding /safeboot/sbin to PATH" >&2
	export PATH=$PATH:/safeboot/sbin
	if [[ -z $1 ]]; then
		return 0
	fi
	if [[ ! -f /safeboot/functions.sh ]]; then
		echo "Error, Safeboot 'functions.sh' isn't installed"
		return 1
	fi
	echo "Sourcing /safeboot/functions.sh"
	source "/safeboot/functions.sh"
}

# Add's /install/{bin,lib[/python3/dist-packages]} to the relevant environment
# variables. Note, unlike need_safeboot, there is no error case, because the
# depended-upon software may be installed via OS-native packages in other
# paths. (That's why it's "add_*" rather than "need_*".)
function add_install {
	if [[ -d "/install/bin" ]]; then
		export PATH=$PATH:/install/bin
		echo "Adding /install/sbin to PATH" >&2
	fi
	if [[ ! -d "/install/lib" ]]; then
		return 0
	fi
	export LD_LIBRARY_PATH=/install/lib:$LD_LIBRARY_PATH
	echo "Adding /install/lib to LD_LIBRARY_PATH" >&2
	if [[ ! -d /install/lib/python3/dist-packages ]]; then
		return 0
	fi
	export PYTHONPATH=/install/lib/python3/dist-packages:$PYTHONPATH
	echo "Adding /install/lib/python3/dist-packages to PYTHONPATH" >&2
}

function show_hcp_env {
	printenv | egrep -e "^HCP_" | sort
}

function export_hcp_env {
	printenv | egrep -e "^HCP_" | sort | sed -e "s/^HCP_/export HCP_/"
}

function hcp_pre_launch {
	if [[ -z $HCP_INSTANCE ]]; then
		echo "Error, HCP_INSTANCE not defined" >&2
		return 1
	fi
	if [[ ! -f $HCP_INSTANCE ]]; then
		echo "Error, HCP_INSTANCE ($HCP_INSTANCE) not found" >&2
		return 1
	fi
	HCP_LAUNCH_DIR=$(dirname "$HCP_INSTANCE")
	HCP_LAUNCH_ENV=$(basename "$HCP_INSTANCE")
	echo "Entering directory '$HCP_LAUNCH_DIR'"
	cd $HCP_LAUNCH_DIR
	if [[ -f common.env ]]; then
		echo "Sourcing common config: common.env"
		source common.env
	fi
	echo "Sourcing specific config: $HCP_LAUNCH_ENV"
	source "$HCP_LAUNCH_ENV"
	# If we're supposed to launch any background tasks (eg. FQDN
	# discovery), use this opportunity.
	/hcp/common/init.sh
}

# The following is flexible support for (re)creating a role account with an
# associated UID file, which is typically in persistent storage. It generalises
# to cases with a single container or multiple distinct containers, using the
# same persistent storage, that need to have an agreed-upon account and UID.
# When the UID file hasn't yet been created, the first caller will create the
# account with a dynamically assigned UID, then print that into the UID file,
# so that subsequent callers (if in distinct containers) can create the same
# account with the same UID. If a container restarts and no longer has the
# account locally, it will do likewise - recreate the account with the UID from
# the UID file.
# NB: because of adduser's semantics, this function doesn't like to race
# against multiple calls of itself. (Collisions and conflicts on creation of
# groups, etc.) So we use a very crude mutex, based on 'mkdir'.
#  $1 - name of the role account
#  $2 - path to the UID file
#  $3 - gecos/finger string for the account
function role_account_uid_file {
	retries=0
	until mkdir /var/lock/hcp_uid_creation; do
		retries=$((retries+1))
		if [[ $retries -eq 5 ]]; then
			echo "Warning, lock contention on role-account creation" >&2
			retries=0
		fi
		sleep 1
	done
	retval=0
	internal_role_account_uid_file "$1" "$2" "$3" || retval=$?
	rmdir /var/lock/hcp_uid_creation
	return $retval
}
function internal_role_account_uid_file {
	if [[ ! -f $2 ]]; then
		if ! egrep "^$1:" /etc/passwd; then
			echo "Creating '$1' role account" >&2
			if ! adduser --disabled-password --quiet \
					--gecos "$3" $1 > /dev/null 2>&1 ; then
				echo "Error, couldn't create '$1'" >&2
				exit 1
			fi
		fi
		echo "Generating '$1' UID file ($2)"
		touch $2
		chown $1 $2
	else
		ENROLLSVC_UID_FLASK=$(stat -c '%u' $2)
		if ! egrep "^$1:" /etc/passwd; then
			echo "Recreating '$1' role account with UID=$ENROLLSVC_UID_FLASK" >&2
			if ! adduser --disabled-password --quiet \
					--uid $ENROLLSVC_UID_FLASK \
					--gecos "$3" $1 > /dev/null 2>&1 ; then
				echo "Error, couldn't recreate '$1'" >&2
				exit 1
			fi
		fi
	fi
}
