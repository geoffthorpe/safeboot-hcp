#!/bin/bash

source /hcp/common/hcp.sh

hcp_pre_launch

export TPM2TOOLS_TCTI=swtpm:path=$HCP_SWTPMSVC_TPMSOCKET

tpm2_pcrread || exit 1
