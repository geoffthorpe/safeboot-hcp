#!/bin/bash

# This script supports the case where enrollsvc::mgmt is creating and running
# an integrated swtpm (not a side-car), and enrolling itself directly with
# db_add.py (not going via the web API). It's not a general purpose enrollment.
source /hcp/enrollsvc/common.sh

expect_db_user

MYPROFILE=$(cat - << EOF
{
	"gencert-hxtool": {
		"list": "default-pkinit-client default-https-client default-https-server"
	}
}
EOF
)

MYOUT=$(mktemp)

# TODO: this is one of those remaining corners of the code that doesn't handle
# unsynchronized startup of the services. There's no retry handling if the
# policysvc hook isn't (yet) avaiable, for example.
if ! python3 /hcp/enrollsvc/db_add.py \
		"$HCP_SWTPMSVC_STATE/tpm/ek.pub" \
		"$HCP_ENROLLSVC_SELFENROLL_HOSTNAME" \
		"$MYPROFILE" > "$MYOUT" 2>&1; then
	echo "Error, self-enrollment failed. Trace output;" >&2
	cat "$MYOUT" >&2
	exit 1
fi
true
