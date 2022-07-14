#!/bin/bash

# This script supports the case where enrollsvc::mgmt is creating and running
# an integrated swtpm (not a side-car), and enrolling itself directly with
# op_add.sh (not going via the web API). It's not a general purpose enrollment.
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

if ! /hcp/enrollsvc/op_add.sh \
		"$HCP_SWTPMSVC_STATE/tpm/ek.pub" \
		"$HCP_ENROLLSVC_SELFENROLL_HOSTNAME" \
		"$MYPROFILE" > "$MYOUT" 2>&1; then
	echo "Error, self-enrollment failed. Trace output;" >&2
	cat "$MYOUT" >&2
	exit 1
fi
true
