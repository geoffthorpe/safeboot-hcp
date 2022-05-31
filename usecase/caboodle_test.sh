#!/bin/bash

source /hcp/caboodle/common.sh

if [[ -n $HCP_CABOODLE_ALONE ]]; then
	hcp_start_all
	hcp_setup_all
fi

hcp_util_run aclient

if [[ -n $HCP_CABOODLE_ALONE ]]; then
	hcp_stop_all
fi
