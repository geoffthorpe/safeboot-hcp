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

if [[ ! -f $HCP_ATTESTSVC_UWSGI_INI ]]; then
	echo "Error, HCP_ATTESTSVC_UWSGI_INI ($HCP_ATTESTSVC_UWSGI_INI) isn't available" >&2
fi

echo "Running 'attestsvc-hcp' service"

# Convince the safeboot scripts to find safeboot.conf and functions.sh and
# the sbin stuff
export DIR=/safeboot
export BINDIR=$DIR

# Steer attest-server (and attest-verify) towards our source of truth
export SAFEBOOT_DB_DIR="$HCP_USER_DIR/current"

# uwsgi takes SIGTERM as an indication to ... reload! So we need to translate
# SIGTERM to SIGQUIT to have the desired effect.
echo "Setting SIGTERM->SIGQUIT trap handler"
UPID=0
trap 'echo "Converting SIGTERM->SIGQUIT"; kill -QUIT $UPID' TERM

TO_RUN="uwsgi_python3 --ini $HCP_ATTESTSVC_UWSGI_INI"
echo "Running: $TO_RUN"
$TO_RUN &
UPID=$!
wait $UPID
