#!/bin/bash

source /hcp/common/hcp.sh

set -e

hcp_pre_launch

[[ -n $HCP_NO_INIT ]] || /hcp/common/init.sh

if [[ $# -gt 0 ]]; then
	echo "Launching '$@'"
	exec $@
fi
if [[ -z $HCP_LAUNCH_BIN ]]; then
	echo "Error, HCP_LAUNCH_BIN not defined" >&2
	return 1
fi
echo "Launching '$HCP_LAUNCH_BIN'"
exec "$HCP_LAUNCH_BIN"
