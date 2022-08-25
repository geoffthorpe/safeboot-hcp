#!/bin/bash

source /hcp/common/hcp.sh

hcp_pre_launch

if [[ $# -gt 0 ]]; then
	echo "Launching '$@'"
	exec $@
fi
if [[ -z $HCP_LAUNCH_BIN ]]; then
	echo "Error, HCP_LAUNCH_BIN not defined" >&2
	return 1
fi

exec $HCP_LAUNCH_BIN
