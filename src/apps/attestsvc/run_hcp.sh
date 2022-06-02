#!/bin/bash

. /hcp/attestsvc/common.sh

expect_root

# Handle lazy-initialization (by waiting for the _repl sub-service to do it).
waitsecs=0
waitinc=3
waitcount=0
until [[ -f $HCP_ATTESTSVC_STATE/initialized ]]; do
	if [[ $((++waitcount)) -eq 10 ]]; then
		echo "Error: state not initialized, failing" >&2
		exit 1
	fi
	if [[ $waitcount -eq 1 ]]; then
		echo "Warning: state not initialized, waiting" >&2
	fi
	sleep $((waitsecs+=waitinc))
	echo "Warning: retrying after $waitsecs-second wait" >&2
done

echo "Running 'attestsvc-hcp' service"

drop_privs_hcp /hcp/attestsvc/flask_wrapper.sh
