#!/bin/bash

source /hcp/common/hcp.sh

set -e

hcp_pre_launch

add_install

export TPM2TOOLS_TCTI=swtpm:path=$HCP_SWTPMSVC_TPMSOCKET

tpm2_pcrread || exit 1
