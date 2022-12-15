#!/bin/bash

source /hcp/common/hcp.sh

log "set-abc-env-file.sh starting"
log " - KRB5_CONFIG=$KRB5_CONFIG"
log " - HCP_CONFIG_FILE=$HCP_CONFIG_FILE"
log " - HCP_CONFIG_SCOPE=$HCP_CONFIG_SCOPE"

cat > /config/hcp.env <<EOF
export KRB5_CONFIG="$KRB5_CONFIG"
export HCP_CONFIG_FILE="$HCP_CONFIG_FILE"
export HCP_CONFIG_SCOPE="$HCP_CONFIG_SCOPE"
EOF

chown abc /config/hcp.env
