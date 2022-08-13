#!/bin/bash

cd $HCP_SWTPMSVC_STATE

# Handle initialization ordering issues by retrying.
waitcount=0
until [[ -d $HCP_SWTPMSVC_STATE/tpm ]]; do
	waitcount=$((waitcount+1))
	if [[ $waitcount -eq 1 ]]; then
		echo "Warning: swtpmsvc waiting for swtpmsvc state to initialize" >&2
	fi
	if [[ $waitcount -eq 11 ]]; then
		echo "Warning: swtpmsvc waited for another 10 seconds" >&2
		waitcount=1
	fi
	sleep 1
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
