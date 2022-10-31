#!/bin/bash

source /hcp/common/hcp.sh

export HCP_SWTPMSVC_STATE=$(hcp_config_extract ".swtpmsvc.state")
export HCP_SWTPMSVC_SOCKDIR=$(hcp_config_extract_or ".swtpmsvc.sockdir")
export HCP_SWTPMSVC_TPMSOCKET="$HCP_SWTPMSVC_SOCKDIR/tpm"

cd $HCP_SWTPMSVC_STATE

# Start the software TPM

echo "Running 'swtpmsvc' service (for $HCP_SWTPMSVC_ENROLL_HOSTNAME)"

echo "Listening on unixio,path=$HCP_SWTPMSVC_TPMSOCKET[.ctrl]"
exec swtpm socket --tpm2 --tpmstate dir=$HCP_SWTPMSVC_STATE/tpm \
	--server type=unixio,path=$HCP_SWTPMSVC_TPMSOCKET \
	--ctrl type=unixio,path=$HCP_SWTPMSVC_TPMSOCKET.ctrl \
	--flags startup-clear > /dev/null 2>&1
