#!/bin/bash

# This gets pointed to by HCP_ENTRYPOINT for containers that are just supposed to
# "exist", in a steady state. Eg. this is useful when you want a stateful entity
# to exist, but for all actions to occur by explicit 'exec' calls from the
# host.

while :; do
	sleep 60
done
