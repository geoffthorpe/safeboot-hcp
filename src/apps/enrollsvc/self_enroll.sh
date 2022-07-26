#!/bin/bash

# This script supports the case where enrollsvc::mgmt is creating and running
# an integrated swtpm (not a side-car), and enrolling itself directly with
# op_add.sh (not going via the web API). It's not a general purpose enrollment.
source /hcp/enrollsvc/common.sh

expect_db_user

MYPROFILE=$(cat - << EOF
{
	"params": {
		"gencert-hxtool": {
			"list": "default-pkinit-client default-https-client default-https-server"
		}
	}
}
EOF
)

MYOUT=$(mktemp)

# Policy checks occur at the API level (mgmt_api.py) as well as the individual
# asset-creation level level (gencert-hxtool). The former picks a random UUID
# as the 'request_uid' for its policy check, and then passes that same
# request_uid (by env-var) for the lower-level policy checks to use the same
# ID. In our case, we're bypassing the API level, but need to give the
# lower-level tools something to work with. Also, we want the policy-checker to
# be able to work with what we send - so, we use a special marker "UUID" for
# internally-generated enrollments; "abcdef-0123456789"
if ! /hcp/enrollsvc/op_add.sh \
		"$HCP_SWTPMSVC_STATE/tpm/ek.pub" \
		"$HCP_ENROLLSVC_SELFENROLL_HOSTNAME" \
		"$MYPROFILE" \
		"abcdef-0123456789" > "$MYOUT" 2>&1; then
	echo "Error, self-enrollment failed. Trace output;" >&2
	cat "$MYOUT" >&2
	exit 1
fi
true
