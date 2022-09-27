#!/bin/bash

# This script exists primarily to support the development workflow, though it
# can be activated in production (or default package installations) if it fits
# the requirement. (It is only engaged if HCP_ENROLLSVC_ENABLE_SELFENROLL is
# set.)
#
# This script supports local enrollments without requiring the enrollsvc::mgmt
# service to be up. This helps avoid circular dependencies for initializing
# systems that are themselves provide part of the enrollment flow.

source /hcp/enrollsvc/common.sh

expect_db_user

MYPROFILE=$(cat - << EOF
{
	"gencert-hxtool": {
		"list": [ "default-pkinit-client", "default-https-client",
			  "default-https-server" ]
	}
}
EOF
)

MYOUT=$(mktemp)

unset WARNED_HEALTHCHECK
unset WARNED_DBADD

function try_self_enroll {
	# If the policy service isn't available, better to figure that out from
	# a healthcheck rather than having db_add.py fail policy checks only
	# after doing some heavy-lifting.
	if [[ -n $HCP_ENROLLSVC_POLICY ]] && ! curl -f -s -G \
			$HCP_ENROLLSVC_POLICY/healthcheck > /dev/null 2>&1; then
		if [[ -z $WARNED_HEALTHCHECK ]]; then
			echo "Warning, policysvc not available yet, polling" >&2
			WARNED_HEALTHCHECK=1
		fi
		return 1
	fi
	if [[ -n $WARNED_HEALTHCHECK ]]; then
		echo "Policysvc now available" >&2
		unset WARNED_HEALTHCHECK
	fi

	# The db_*.py scripts use http status codes as their exit codes, so if
	# we're not careful they always appear to be failing (0 isn't a valid
	# http status code). We are expecting 201 for an "add" operation.
	myret=0
	python3 /hcp/enrollsvc/db_add.py add \
			"$HCP_SWTPMSVC_STATE/tpm/ek.pub" \
			"$HCP_ENROLLSVC_SELFENROLL_HOSTNAME" \
			"$MYPROFILE" > "$MYOUT" 2>&1 || myret=$?
	if [[ $myret != 201 ]]; then
		if [[ -z $WARNED_DBADD ]]; then
			cat "$MYOUT" > $HOME/debug-self-enroll
			echo -n "Warning, self-enrollment failed. Trace output" >&2
			echo " copied to $HOME/debug-self-enroll" >&2
			WARNED_DBADD=1
		fi
		return 1
	fi
	if [[ -n $WARNED_DBADD ]]; then
		echo "Self-enrollment finally succeeded" >&2
		unset WARNED_DBADD
	fi
	return 0
}

echo "Doing self-enrollment" >&2
while ! try_self_enroll; do
	sleep 1
done
true
