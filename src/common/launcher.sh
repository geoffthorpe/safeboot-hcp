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

### NOTE: ###
# The code and comments below are for historical reference, the "exec" just
# above ensures the stuff below is never reached. We've moved to using "--init"
# when invoking docker directly, and for the docker-compose case we use the
# equivalent "init: true" flag in the docker-compose.yml file. This causes a
# PID1 process to run in the container to reap orphaned processes and forward
# signals, precisely as the below workarounds were doing for us. Why keep the
# code around? Well ... if we run into a version of docker/docker-compose that
# doesn't support --init, or if we discover glitches, the stuff below may well
# come in handy.
#############

echo "ERROR, this code isn't supposed to run"
exit 1

# If we run $HCP_LAUNCH_BIN synchronously as a child process, bash ignores
# signals until it returns, so our UX can suffer as a result. (Eg. if bash is
# the parent in the container, then attempts to stop the container usually
# takes time and doesn't perform controlled shutdown, because the graceful
# SIGTERM is ignored, so an ungraceful SIGKILL typically comes 10 seconds
# later.)
#
# Or, we could "exec $HCP_LAUNCH_BIN" to make bash go away and be replaced by
# the thing we're trying to launch, but then we lose a useful feature of having
# bash be a parent - namely it always reaps processes for which it is a parent,
# just like 'init'. In a container, PID 1 usually isn't init, so if it isn't
# bash either, orphaned processes getting re-parented to PID 1 typically don't
# benefit from auto-reaping, therefore zombies accumulate.
#
# Our solution;
# - keep bash as the parent process
# - run $HCP_LAUNCH_BIN in the background (asynchronously) and record its PID
# - set traps to handle and propagate SIGQUIT and SIGTERM to the child
# - block in the 'wait' call, which (unlike a synchronous call) _will_ break
#   when signals arrive, so the traps can run.
echo "Setting SIGQUIT and SIGTERM trap handlers"
trap 'echo "Caught SIGQUIT"; kill -QUIT $child_pid' QUIT
trap 'echo "Caught SIGTERM"; kill -TERM $child_pid' TERM
echo "Launching '$HCP_LAUNCH_BIN'"
"$HCP_LAUNCH_BIN" &
child_pid=$!
wait $child_pid
