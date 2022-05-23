#!/bin/bash

function show_hcp_env {
	printenv | egrep -e "^HCP_" | sort
}

function export_hcp_env {
	printenv | egrep -e "^HCP_" | sort | sed -e "s/^HCP_/export HCP_/"
}

function hcp_pre_launch {
	if [[ -z $HCP_INSTANCE ]]; then
		echo "Error, HCP_INSTANCE not defined" >&2
		return 1
	fi
	if [[ ! -f $HCP_INSTANCE ]]; then
		echo "Error, HCP_INSTANCE ($HCP_INSTANCE) not found" >&2
		return 1
	fi
	HCP_LAUNCH_DIR=$(dirname "$HCP_INSTANCE")
	HCP_LAUNCH_ENV=$(basename "$HCP_INSTANCE")
	echo "Entering directory '$HCP_LAUNCH_DIR'"
	cd $HCP_LAUNCH_DIR
	if [[ -f common.env ]]; then
		echo "Sourcing common config: common.env"
		source common.env
	fi
	echo "Sourcing specific config: $HCP_LAUNCH_ENV"
	source "$HCP_LAUNCH_ENV"
}
