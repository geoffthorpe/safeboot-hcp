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

# Done!
touch "$HCP_ATTESTSVC_LOCAL_INIT"
