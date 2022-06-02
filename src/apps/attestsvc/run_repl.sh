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

# Handle lazy-initialization.
if [[ ! -f $HCP_ATTESTSVC_STATE/initialized ]]; then
	echo "Initializing attestsvc state"
	# This is the one-time init hook, so make sure the mounted dir has
	# appropriate ownership
	chown hcp_user:hcp_user $HCP_ATTESTSVC_STATE
	# drop_privs_*() performs an 'exec su', so we run this in a child
	# process.
	(drop_privs_hcp /hcp/attestsvc/init_clones.sh)
	touch $HCP_ATTESTSVC_STATE/initialized
	echo "State now initialized"
fi


echo "Running 'attestsvc-repl' service"

drop_privs_hcp /hcp/attestsvc/updater_loop.sh
