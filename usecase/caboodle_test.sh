#!/bin/bash

echo "CABOODLE_TEST: pre-processing"
source /hcp/caboodle/common.sh

if [[ -n $HCP_CABOODLE_ALONE ]]; then
	echo "CABOODLE_TEST: starting all services"
	hcp_start_all
	echo "CABOODLE_TEST: waiting for emgmt to come up"
	hcp_util_run wait_emgmt
	echo "CABOODLE_TEST: running orchestrator"
	hcp_setup_all
	echo "CABOODLE_TEST: waiting for ahcp to come up"
	hcp_util_run wait_ahcp
fi

echo "CABOODLE_TEST: waiting for swtpm to come up"
hcp_util_run wait_aclient_tpm
echo "CABOODLE_TEST: running attestation client"
hcp_util_run aclient

if [[ -n $HCP_CABOODLE_ALONE ]]; then
	echo "CABOODLE_TEST: stopping all services"
	hcp_stop_all
fi
