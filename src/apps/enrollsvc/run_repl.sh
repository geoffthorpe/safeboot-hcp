#!/bin/bash

(
	if [[ ! -d $HCP_ENROLLSVC_STATE ]]; then
		echo "Error, HCP_ENROLLSVC_STATE ($HCP_ENROLLSVC_STATE) doesn't exist" >&2
		exit 1
	fi

	waitcount=0
	until [[ -f $HCP_ENROLLSVC_STATE/initialized ]]; do
		waitcount=$((waitcount+1))
		if [[ $waitcount -eq 1 ]]; then
			echo "Warning: waiting for enrollsvc state to initialize" >&2
		fi
		if [[ $waitcount -eq 11 ]]; then
			echo "Warning: waited for another 10 seconds" >&2
			waitcount=1
		fi
		sleep 1
	done
)

. /hcp/enrollsvc/common.sh

expect_root

echo "Running 'enrollsvc-repl' service (git-daemon)"

GITDAEMON=${HCP_ENROLLSVC_GITDAEMON:=/usr/lib/git-core/git-daemon}
GITDAEMON_FLAGS=${HCP_ENROLLSVC_GITDAEMON_FLAGS:=--reuseaddr --listen=0.0.0.0 --port=9418}

TO_RUN="$GITDAEMON \
	--base-path=$HCP_DB_DIR \
	$GITDAEMON_FLAGS \
	$REPO_PATH"

echo "Running (as db_user): $TO_RUN"
drop_privs_db $TO_RUN
