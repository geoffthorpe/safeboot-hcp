#!/bin/bash

source /hcp/common/hcp.sh

hcp_pre_launch

URL=${HCP_EMGMT_HOSTNAME}.${HCP_FQDN_DEFAULT_DOMAIN}
CERTARG=""
if [[ -n $HCP_EMGMT_ENABLE_NGINX ]]; then
	URL=https://$URL:8443
	CERTARG="--cert /etc/ssl/hostcerts/hostcert-default-https-client-key.pem"
else
	URL=http://$URL:5000
fi
URL=$URL/healthcheck

curl -f -G $CERTARG $URL
