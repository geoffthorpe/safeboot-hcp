#!/bin/bash

# The reenroller runs with dropped privs.
# Here, we do the outer loop, so that the actual reenrollment code
# (reenroller_sub.py) implements just a single pass and doesn't need to retain
# any state.

source /hcp/enrollsvc/common.sh

expect_db_user

jperiod=$(hcp_config_extract '.reenroller.period')
jretry=$(hcp_config_extract '.reenroller.retry')

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
