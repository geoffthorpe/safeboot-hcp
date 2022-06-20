#!/bin/bash

# This callback can be used to look for a 'certissuer.pem' file and install it
# as a trust root on the host.

if [[ ! -f certissuer.pem ]]; then
	echo "No 'certissuer.pem' found, skipping" >&2
	exit 0
fi

source /hcp/common/hcp.sh

add_trust_root certissuer.pem HCP certissuer.pem
