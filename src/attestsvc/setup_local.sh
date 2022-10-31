#!/bin/bash

source /hcp/attestsvc/common.sh

expect_root

if [[ ! -f $HCP_ATTESTSVC_GLOBAL_INIT ]]; then
	echo "Error, setup_local.sh being run before setup_global.sh" >&2
	exit 1
fi

if [[ -f "$HCP_ATTESTSVC_LOCAL_INIT" ]]; then
	echo "Error, setup_local.sh being run but already initialized" >&2
	exit 1
fi

echo "Initializing (rootfs-local) attestsvc state"

# (Re)create the users, pulling their user ids from persistent state.
do_attestsvc_uid_setup

# Done!
touch "$HCP_ATTESTSVC_LOCAL_INIT"
