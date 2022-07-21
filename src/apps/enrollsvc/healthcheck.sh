#!/bin/bash

source /hcp/common/hcp.sh

hcp_pre_launch

URL=${HCP_EMGMT_HOSTNAME}.${HCP_FQDN_DEFAULT_DOMAIN}
if [[ -n $HCP_EMGMT_ENABLE_NGINX ]]; then
	URL=https://$URL:8443
else
	URL=http://$URL:5000
fi
URL=$URL/healthcheck

curl -f -G --cert /etc/ssl/hostcerts/hostcert-default-https-client.pem $URL
