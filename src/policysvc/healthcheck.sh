#!/bin/bash

source /hcp/common/hcp.sh

URL=${HCP_POLICYSVC_URL}/healthcheck

curl -f -G $URL
