#!/bin/bash

. /hcp/swtpmsvc/common.sh

# Handle initialization ordering issues by retrying.
waitsecs=0
waitinc=3
waitcount=0
while [[ ! -d $HCP_SWTPMSVC_STATE/tpm ]]; do
	if [[ $((++waitcount)) -eq 10 ]]; then
		echo "Error: swtpmsvc state uninitialized" >&2
		exit 1
	fi
	sleep $((waitsecs+=waitinc))
	echo "Warning, waiting for TPM to be initialized" >&2
done

TPMPORT1=9876
TPMPORT2=9877

# Start the software TPM

echo "Running 'swtpmsvc' service (for $HCP_SWTPMSVC_ENROLL_HOSTNAME)"

if [[ -n "$HCP_SWTPMSVC_TPMSOCKET" ]]; then
	echo "Listening on unixio,path=$HCP_SWTPMSVC_TPMSOCKET[.ctrl]"
	exec swtpm socket --tpm2 --tpmstate dir=$HCP_SWTPMSVC_STATE/tpm \
		--server type=unixio,path=$HCP_SWTPMSVC_TPMSOCKET \
		--ctrl type=unixio,path=$HCP_SWTPMSVC_TPMSOCKET.ctrl \
		--flags startup-clear > /dev/null 2>&1
else
	echo "Listening on tcp,port=$TPMPORT1/$TPMPORT2"
	exec swtpm socket --tpm2 --tpmstate dir=$HCP_SWTPMSVC_STATE/tpm \
		--server type=tcp,bindaddr=0.0.0.0,port=$TPMPORT1 \
		--ctrl type=tcp,bindaddr=0.0.0.0,port=$TPMPORT2 \
		--flags startup-clear > /dev/null 2>&1
fi
