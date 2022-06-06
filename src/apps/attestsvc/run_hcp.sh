#!/bin/bash

(
	if [[ ! -d $HCP_ATTESTSVC_STATE ]]; then
		echo "Error, HCP_ATTESTSVC_STATE ($HCP_ATTESTSVC_STATE) doesn't exist" >&2
		exit 1
	fi

	# Handle lazy-initialization (by waiting for the _repl sub-service to do it).
	waitcount=0
	until [[ -f $HCP_ATTESTSVC_STATE/initialized ]]; do
		waitcount=$((waitcount+1))
		if [[ $waitcount -eq 1 ]]; then
			echo "Warning: waiting for attestsvc state to initialize" >&2
		fi
		if [[ $waitcount -eq 11 ]]; then
			echo "Warning: waited for another 10 seconds" >&2
			waitcount=1
		fi
		sleep 1
	done
)

. /hcp/attestsvc/common.sh

expect_root

echo "Running 'attestsvc-hcp' service"

drop_privs_hcp /hcp/attestsvc/flask_wrapper.sh
