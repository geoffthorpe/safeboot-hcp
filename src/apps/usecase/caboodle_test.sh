#!/bin/bash

source /hcp/caboodle/common.sh

if [[ -n $HCP_CABOODLE_ALONE ]]; then
	hcp_services_start

	echo "Running HCP orchestrator"
	HCP_INSTANCE=./orchestrator.env /hcp/common/launcher.sh
fi

echo "Running HCP attestation client"
HCP_INSTANCE=./attestclient.env /hcp/common/launcher.sh

if [[ -n $HCP_CABOODLE_ALONE ]]; then
	hcp_services_stop
fi
