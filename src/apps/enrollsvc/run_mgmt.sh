#!/bin/bash

# By cd'ing to /, we make sure we're not influenced by the directory we were
# launched from.
cd /

source /hcp/enrollsvc/common.sh

expect_root

if [[ -n $HCP_ENROLLSVC_ENABLE_SWTPM ]]; then

	if [[ ! -f "$HCP_SWTPMSVC_STATE/tpm/ek.pub" ]]; then
		echo "Creating local swtpm instance for $HCP_HOSTNAME"
		export HCP_ORCHESTRATOR_JSON=$(mktemp)
		cat > $HCP_ORCHESTRATOR_JSON << EOF
{ "fleet": [ {
	"name": "emgmt",
	"tpm_create": true,
	"tpm_path": "$HCP_SWTPMSVC_STATE",
	"enroll": false
} ] }
EOF
		/hcp/tools/run_orchestrator.sh
		rm $HCP_ORCHESTRATOR_JSON
	fi

	echo "Starting local swtpm instance for $HCP_HOSTNAME"
	# Background the swtpm instance. Note, we don't want anything mounted
	# at $HCP_EMGMT_ATTEST_TCTI_SOCKDIR to facilitate access to a swtpm
	# container precisely because we're choosing to have it running
	# locally/internally. We need to create the directory here instead.
	mkdir -p $HCP_EMGMT_ATTEST_TCTI_SOCKDIR
	/hcp/swtpmsvc/run_swtpm.sh &

	# Handle self-enrollment of private swtpmsvc
	if [[ -n $HCP_ENROLLSVC_ENABLE_SWTPM_SELFENROLL &&
			! -f "$HCP_ENROLLSVC_STATE/self-enrolled" ]]; then
		echo "Self-enrolling swtpm EK"
		chmod 644 "$HCP_SWTPMSVC_STATE/tpm/ek.pub"
		(drop_privs_db /hcp/enrollsvc/self_enroll.sh)
		touch "$HCP_ENROLLSVC_STATE/self-enrolled"
	fi
fi

if [[ -n $HCP_ENROLLSVC_ENABLE_ATTEST ]]; then
	# Run the attestation and get our assets
	# Note, run_client is not a service, it's a utility, so it doesn't
	# retry forever waiting for things to be ready to succeed. We, on the
	# other hand, _are_ a service, so we need to be more forgiving.
	echo "Running attestation client"
	attestlog=$(mktemp)
	if ! /hcp/tools/run_client.sh 2> $attestlog; then
		echo "Warning: the attestation client lost patience, error output follows;" >&2
		cat $attestlog >&2
		rm $attestlog
		echo "Warning: suppressing error output from future attestation attempts" >&2
		attestation_done=
		until [[ -n $attestation_done ]]; do
			echo "Warning: waiting 10 seconds before retring attestation" >&2
			sleep 10
			echo "Retrying attestation" >&2
			/hcp/tools/run_client.sh 2> /dev/null && attestation_done=yes
		done
	fi
fi

if [[ -n $HCP_ENROLLSVC_ENABLE_NGINX ]]; then
	# Copy the nginx config into place and start the service.
	cp "$HCP_ENROLLSVC_NGINX_CONF" /etc/nginx/sites-enabled/
	nginx
	NGPID=$(cat /run/nginx.pid)
else
	NGPID=0
fi

# Do common.sh-style things that are specific to the management sub-service.
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
# SIGTERM to SIGQUIT to have the desired effect. Also kill nginx if it's
# running.
echo "Setting SIGTERM->SIGQUIT trap handler for uwsgi"
UPID=0
trap 'echo "Converting SIGTERM->SIGQUIT"; kill -QUIT $UPID; kill -TERM $NGPID' TERM

TO_RUN="uwsgi_python3 --ini $HCP_ENROLLSVC_UWSGI_INI"
echo "Running: $TO_RUN"
$TO_RUN &
UPID=$!
wait $UPID
