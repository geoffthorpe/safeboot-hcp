#!/bin/bash

# This script gets set as the ENTRYPOINT for all HCP containers, so it's where
# we load (and export!) environment variables that we rely on.

log() {
	if [[ -n $VERBOSE ]]; then
		echo "$1" >&2
	fi
}

log "HCP launcher: sourcing /hcp/common/hcp.sh"
source /hcp/common/hcp.sh

# This function (implemented in hcp.sh) loads instance-specific environment
# settings based on the HCP_INSTANCE environment variable. Ie. when starting
# the container, if HCP_INSTANCE is set then we source the file it points to
# (and if there is a common.env in the same directory, we source that too).
# This also starts any backgrounded tasks are expected (usually indicated by
# environment that is loaded from HCP_INSTANCE)
log "HCP launcher: running hcp_pre_launch() function"
hcp_pre_launch

# If the caller specified a command to run, that shows up in $@ (which is "$1
# $2 $3 ...").
log "HCP launcher: executing '$1' with arguments: $(shift && echo "$@")"
exec $@

# This should be unreachable
echo "HCP launcher: BUG!!" >&2
exit 1
