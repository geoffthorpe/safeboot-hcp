#!/bin/bash

source /hcp/common/hcp.sh

log "set-container-env.sh starting"
log " - HCP_IN_MONOLITH=$HCP_IN_MONOLITH"
log " - HCP_CONFIG_FILE=$HCP_CONFIG_FILE"
log " - HCP_CONFIG_SCOPE=$HCP_CONFIG_SCOPE"

log " - writing /etc/hcp-monolith-container.env"
cat > /etc/hcp-monolith-container.env <<EOF
export HCP_IN_MONOLITH="$HCP_IN_MONOLITH"
export HCP_CONFIG_FILE="$HCP_CONFIG_FILE"
export HCP_CONFIG_SCOPE="$HCP_CONFIG_SCOPE"
EOF
