#!/bin/bash

set -e

# We need a unique ID that can be passed to docker-compose via the '-p'
# flag, to ensure that any and all containers (and networks) that get
# started up are isolated from anything else that may have been running
# or that may get run later.
TESTUID=$(date +p_%s_%N)
DCOMPOSE="docker-compose --project-name $TESTUID"
export DCOMPOSE

# This wrapper sources the test script (at HCP_TEST_PATH) after setting a trap
# handler to clean up.

if [[ -z $HCP_TEST_PATH ]]; then
	echo "ERROR, HCP_TEST_PATH isn't defined"
	exit 1
fi

trap '$DCOMPOSE down -v' ERR EXIT

source $HCP_TEST_PATH

echo "Success"
