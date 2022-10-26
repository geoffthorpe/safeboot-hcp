#!/bin/bash

set -e

step()
{
	text=$1
	shift
	echo "SERVICES_TEST: $text"
	if [[ $# == 0 ]]; then
		return
	fi
	if [[ $VERBOSE -gt 0 ]]; then
		echo "$DCOMPOSE $@"
	fi
	if [[ $VERBOSE -gt 1 ]]; then
		$DCOMPOSE $@
	else
		# Not verbose, so buffer the output and leave breadcrumbs only
		# if the command fails.
		rc=0
		$DCOMPOSE $@ > $outfile 2> $errfile || rc=$?
		if [[ $rc != 0 ]]; then
			echo "FAIL: exit code '$rc' from command;"
			echo "  docker-compose $@"
			echo "The command's output is at;"
			echo "stdout: $outfile"
			echo "stderr: $errfile"
			outfile=
			errfile=
			exit $rc
		fi
	fi
}

# This will force VERBOSE to be an integer. If it was set to something else, or
# not set at all, it will become zero.
VERBOSE=$((VERBOSE))
if [[ $VERBOSE -eq 0 ]]; then
	step "running quietly (set VERBOSE=1 to see commands, VERBOSE=2 for all the action)"
else
	step "running VERBOSE=$VERBOSE"
fi

if [[ -z $RETRIES ]]; then
	RETRIES=60
	step "RETRIES=60 (default)"
else
	RETRIES=$((RETRIES))
	step "RETRIES=$RETRIES (from environment)"
fi


# Find temporary files for buffering command output until we know whether it
# needs displaying or not. Clean up on exit, unless the variables have
# (intentionally) been reset to empty.
outfile=
errfile=
function trapper {
	[[ -n $outfile ]] && rm $outfile
	[[ -n $errfile ]] && rm $errfile
}
trap trapper EXIT
outfile=$(mktemp)
errfile=$(mktemp)

step "starting all services" \
	up -d emgmt_pol emgmt erepl arepl ahcp aclient_tpm

step "waiting for emgmt to come up" \
	exec emgmt /hcp/enrollsvc/emgmt_healthcheck.sh -R $RETRIES

step "running orchestrator" \
	run orchestrator -c -e aclient

step "waiting for ahcp to come up" \
	exec ahcp /hcp/attestsvc/ahcp_healthcheck.sh -R $RETRIES

step "waiting for swtpm to come up" \
	exec aclient_tpm /hcp/swtpmsvc/healthcheck.sh -R $RETRIES

step "running attestation client" \
	run aclient -R $RETRIES

step "SERVICES_TEST: stopping all services"
# The trap in wrapper.sh takes care of stopping things
