#!/bin/bash

# The reenroller runs with dropped privs so it loses the caller's environment
# and needs to pick it up again from this common.sh. It's "difficult" for a
# python script to source a bash one, so this stub exists to source common.sh
# and then run the python reenrollment code. And seeing as we have a bash
# script to kick things off, we'll also have it do the outer loop, so that the
# python reenrollment code only needs to implement a single pass and doesn't
# need to retain any state over time. (So no issues with reloading
# configuration, log rotation, restartability, ...)

source /hcp/enrollsvc/common.sh

expect_db_user

S_OK=$HCP_ENROLLSVC_REENROLLER_PERIOD
S_ERR=$HCP_ENROLLSVC_REENROLLER_BACKOFF

while : ; do
	python3 /hcp/enrollsvc/reenroller_sub.py && sleep $S_OK ||
		(echo "Warning: reenroller encountered error: sleep $S_ERR" &&
			sleep $S_ERR)
done
