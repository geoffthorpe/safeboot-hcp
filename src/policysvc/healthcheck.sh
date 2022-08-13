#!/bin/bash

source /hcp/common/hcp.sh

hcp_pre_launch

URL=${HCP_POL_HOSTNAME}.${HCP_FQDN_DEFAULT_DOMAIN}
URL=http://$URL:9080
URL=$URL/healthcheck

curl -f -G $URL
