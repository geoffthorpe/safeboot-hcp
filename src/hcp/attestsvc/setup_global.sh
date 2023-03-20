#!/bin/bash

source /hcp/attestsvc/common.sh

expect_root

if [[ ! -d $HCP_ATTESTSVC_STATE ]]; then
	echo "Error, attestsvc::state isn't a directory: $HCP_ATTESTSVC_STATE" >&2
	exit 1
fi

if [[ -f $HCP_ATTESTSVC_GLOBAL_INIT ]]; then
	echo "Error, setup_global.sh being run but already initialized:" >&2
	exit 1
fi

echo "Initializing (persistent) attestsvc state"

# For now we only support one command-line parameter, '--retry'
retry=
if [[ $1 == "--retry" ]]; then
	echo "- will retry until successful"
	retry=1
fi

while :; do
	# Finally, the main thing: run init_repo as the 'emgmtdb' user. This
	# sets up a new enrollment database. In the retry case, we start the
	# loop by removing anything left from the previous loop.
	if [[ -n $retry && -d $HCP_ATTESTSVC_DB_DIR ]]; then
		echo "- retrying"
		rm -rf $HCP_ATTESTSVC_DB_DIR
	fi
	echo " - generating $HCP_ATTESTSVC_USER_DB-owned data in '$HCP_ATTESTSVC_DB_DIR'"
	mkdir $HCP_ATTESTSVC_DB_DIR
	chown $HCP_ATTESTSVC_USER_DB $HCP_ATTESTSVC_DB_DIR
	echo " - initializing repo"
	if ( drop_privs_db /hcp/attestsvc/init_clones.sh ); then
		break
	fi
	if [[ -z $retry ]]; then
		echo "Failed to initialize"
		exit 1
	fi
	echo " - failure, will retry"
	sleep 1
done

# Mark it all as done (services may be polling on the existence of this file).
touch "$HCP_ATTESTSVC_GLOBAL_INIT"
echo "State now initialized"
