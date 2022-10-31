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

# Create the users, and snapshot their user ids into persistent state (so
# future (re)creation of the accounts will (re)use the same uids).
do_attestsvc_uid_setup

# Finally, the main thing: run init_repo as the 'emgmtdb' user. This sets up a
# new enrollment database.
echo " - generating $HCP_ATTESTSVC_USER_DB-owned data in '$HCP_ATTESTSVC_DB_DIR'"
mkdir $HCP_ATTESTSVC_DB_DIR
chown $HCP_ATTESTSVC_USER_DB $HCP_ATTESTSVC_DB_DIR
echo "   - initializing repo"
(drop_privs_db /hcp/attestsvc/init_clones.sh)

# Mark it all as done (services may be polling on the existence of this file).
touch "$HCP_ATTESTSVC_GLOBAL_INIT"
echo "State now initialized"
