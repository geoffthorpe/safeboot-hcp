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

# When we finally get rid of our dependence on env-vars for startup (and
# base everything off the JSON input instead), this bash script and a few
# others could be converted to python, in which case we'd use hcp_tracefile
# and add a bunch of debug-logging about the JSON processing. But for now,
# especially given that our stderr is the top-level/console stderr, we
# stay relatively quiet.

if [[ -z $HCP_ENROLLSVC_JSON || ! -f $HCP_ENROLLSVC_JSON ]]; then
	echo "Error, reenroller has no HCP_ENROLLSVC_JSON" >&2
	exit 1
fi
jsonpath=$HCP_ENROLLSVC_JSON

# We're bash, not python, so we can't use hcp_common.py::dict_timedelta.
# We use hcp.sh::dict_timedelta instead.
jperiod=$(jq -r '.reenroller.period // {}' $jsonpath)
jretry=$(jq -r '.reenroller.retry // {}' $jsonpath)

S_OK=$(dict_timedelta "$jperiod")
S_ERR=$(dict_timedelta "$jretry")
echo "reenroller running with period=$S_OK, retry=$S_ERR"

while : ; do
	# NB: as with all python files that use hcp_tracefile, this will cause
	# a line of logging to be written to the _current_ stderr that tells it
	# about the tracefile being opened, after which that tracefile will
	# replace stderr for subsequent processing and logging. Fine. However
	# this means that for each iteration of this loop, the top-level
	# console stderr gets a message saying that reenroller_sub.py has
	# opened a tracefile. _That_ is why we redirect stderr to /dev/null
	# here - it suppresses that one message to stderr, otherwise all the
	# subsequent logging goes to the tracefile(s).
	python3 /hcp/enrollsvc/reenroller_sub.py > /dev/null 2>&1 &&
		sleep $S_OK ||
		(echo "Warning: reenroller encountered error: sleep $S_ERR" &&
			sleep $S_ERR)
done
