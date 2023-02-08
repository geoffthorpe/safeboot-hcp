#!/bin/bash

# This gets pointed to as an entrypoint for containers that are just supposed
# to "exist", in a steady state. Eg. this is useful when you want a stateful
# entity to exist, but for all actions to occur by explicit 'exec' calls from
# the host. We also use it when the container's main script backgrounds
# everything (rather than exec'ing to one of its tasks) - ie. it serves as an
# idle loop.

while :; do
	sleep 60
done
