#!/bin/bash

. /hcp/attestsvc/common.sh

expect_root

# Do common.sh-style things that are specific to the replication sub-service.
if [[ -z "$HCP_ATTESTSVC_REMOTE_REPO" ]]; then
	echo "Error, HCP_ATTESTSVC_REMOTE_REPO (\"$HCP_ATTESTSVC_REMOTE_REPO\") must be set" >&2
	exit 1
fi
if [[ -z "$HCP_ATTESTSVC_UPDATE_TIMER" ]]; then
	echo "Error, HCP_ATTESTSVC_UPDATE_TIMER (\"$HCP_ATTESTSVC_UPDATE_TIMER\") must be set" >&2
	exit 1
fi

echo "Running 'attestsvc-repl' service"

drop_privs_hcp /hcp/attestsvc/updater_loop.sh
