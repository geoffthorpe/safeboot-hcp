#!/bin/bash

source /hcp/sshsvc/common.sh

if [[ ! -d $HCP_SSHSVC_STATE ]]; then
	echo "Error, sshsvc::state isn't a directory: $HCP_SSHSVC_STATE" >&2
	exit 1
fi

if [[ -f $HCP_SSHSVC_GLOBAL_INIT ]]; then
	echo "Error, setup_global.sh being run but already initialized:" >&2
	exit 1
fi

echo "Initializing (persistent) sshsvc state"

# Create some expected accounts
role_account_uid_file user1 $HCP_SSHSVC_STATE/uid-user1 "Test User 1,,,,"
role_account_uid_file user2 $HCP_SSHSVC_STATE/uid-user2 "Test User 2,,,,"
role_account_uid_file user3 $HCP_SSHSVC_STATE/uid-user3 "Test User 3,,,,"
role_account_uid_file alicia $HCP_SSHSVC_STATE/uid-alicia "Alicia Not-Alice,,,,"
role_account_uid_file abc $HCP_SSHSVC_STATE/abc "ABC User,,,,"

# Mark it all as done (services may be polling on the existence of this file).
touch "$HCP_SSHSVC_GLOBAL_INIT"
echo "State now initialized"
