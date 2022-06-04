#!/bin/bash

. /hcp/enrollsvc/common.sh

expect_root

# Do common.sh-style things that are specific to the replication sub-service.
if [[ ! -f "$SIGNING_KEY_PUB" || ! -f "$SIGNING_KEY_PRIV" ]]; then
	echo "Error, SIGNING_KEY_{PUB,PRIV} ($SIGNING_KEY_PUB,$SIGNING_KEY_PRIV) do not contain valid creds" >&2
	exit 1
fi
if [[ ! -f "$GENCERT_CA_CERT" || ! -f "$GENCERT_CA_PRIV" ]]; then
	echo "Error, GENCERT_CA_CERT ($GENCERT_CA_CERT,$GENCERT_CA_PRIV) do not contain valid creds" >&2
	exit 1
fi
if [[ -z "$HCP_ENROLLSVC_REALM" ]]; then
	echo "Error, HCP_ENROLLSVC_REALM must be set" >&2
fi

echo "Running 'enrollsvc-mgmt' service"

drop_privs_flask /hcp/enrollsvc/flask_wrapper.sh
