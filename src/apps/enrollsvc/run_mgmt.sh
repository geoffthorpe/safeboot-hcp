#!/bin/bash

. /hcp/enrollsvc/common.sh

expect_root

# Do common.sh-style things that are specific to the replication sub-service.
if [[ ! -f $SIGNING_KEY_PUB || ! -f $SIGNING_KEY_PRIV ]]; then
	echo "Error, SIGNING_KEY_{PUB,PRIV} ($SIGNING_KEY_PUB,$SIGNING_KEY_PRIV) do not contain valid creds" >&2
	exit 1
fi
if [[ ! -f $GENCERT_CA_CERT || ! -f $GENCERT_CA_PRIV ]]; then
	echo "Error, GENCERT_CA_CERT ($GENCERT_CA_CERT,$GENCERT_CA_PRIV) do not contain valid creds" >&2
	exit 1
fi
if [[ -z $HCP_ENROLLSVC_REALM ]]; then
	echo "Error, HCP_ENROLLSVC_REALM must be set" >&2
fi
if [[ ! -f $HCP_ENROLLSVC_UWSGI_INI ]]; then
	echo "Error, HCP_ENROLLSVC_UWSGI_INI ($HCP_ENROLLSVC_UWSGI_INI) isn't available" >&2
fi

echo "Running 'enrollsvc-mgmt' service"

# uwsgi takes SIGTERM as an indication to ... reload! So we need to translate
# SIGTERM to SIGQUIT to have the desired effect.
echo "Setting SIGTERM->SIGQUIT trap handler"
UPID=0
trap 'echo "Converting SIGTERM->SIGQUIT"; kill -QUIT $UPID' TERM

TO_RUN="uwsgi_python3 --ini $HCP_ENROLLSVC_UWSGI_INI"
echo "Running: $TO_RUN"
$TO_RUN &
UPID=$!
wait $UPID
