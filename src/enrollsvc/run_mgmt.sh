#!/bin/bash

# By cd'ing to /, we make sure we're not influenced by the directory we were
# launched from.
cd /

source /hcp/enrollsvc/common.sh

expect_root

echo "Running 'enrollsvc-mgmt' service"

if [[ -z $HCP_ENROLLSVC_JSON || ! -f $HCP_ENROLLSVC_JSON ]]; then
	echo "Error, HCP_ENROLLSVC_JSON ('$HCP_ENROLLSVC_JSON') missing" >&2
	exit 1
fi
reenroller=$(jq -r '.reenroller // empty' $HCP_ENROLLSVC_JSON)

if [[ -n $HCP_ENROLLSVC_ENABLE_NGINX ]]; then
	echo "enrollsvc::mgmt, running nginx as front-end proxy"
	# Copy the nginx config into place and start the service.
	cp "$HCP_ENROLLSVC_NGINX_CONF" /etc/nginx/sites-enabled/
	nginx
fi

if [[ -n $reenroller ]]; then
	echo "enrollsvc::mgmt, starting reenroller"
	drop_privs_db /hcp/enrollsvc/reenroller.sh &
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

echo "enrollsvc::mgmt, running uwsgi with the python flask app"
exec uwsgi_python3 --ini $HCP_ENROLLSVC_UWSGI_INI
