#!/bin/bash

. /hcp/common/hcp.sh

set -e

mkdir -p $HCP_ATTESTCLIENT_VERIFIER

if [[ -z "$HCP_ATTESTCLIENT_ATTEST_URL" ]]; then
	echo "Error, HCP_ATTESTCLIENT_ATTEST_URL (\"$HCP_ATTESTCLIENT_ATTEST_URL\") is not set"
	exit 1
fi
if [[ -z "$HCP_ATTESTCLIENT_TPM2TOOLS_TCTI" ]]; then
	echo "Error, HCP_ATTESTCLIENT_TPM2TOOLS_TCTI (\"$HCP_ATTESTCLIENT_TPM2TOOLS_TCTI\") is not set"
	exit 1
fi
export TPM2TOOLS_TCTI=$HCP_ATTESTCLIENT_TPM2TOOLS_TCTI
if [[ -z "$HCP_ATTESTCLIENT_VERIFIER" || ! -d "$HCP_ATTESTCLIENT_VERIFIER" ]]; then
	echo "Error, HCP_ATTESTCLIENT_VERIFIER (\"$HCP_ATTESTCLIENT_VERIFIER\") is not a valid directory" >&2
	exit 1
fi
export ENROLL_SIGN_ANCHOR=$HCP_ATTESTCLIENT_VERIFIER/key.pem
if [[ ! -f "$ENROLL_SIGN_ANCHOR" ]]; then
	echo "Error, HCP_ATTESTCLIENT_VERIFIER does not contain key.pem" >&2
	exit 1
fi

add_install
need_safeboot 1

# The following helps to convince the safeboot scripts to find safeboot.conf
# and functions.sh
export DIR=/safeboot
cd $DIR

# passed in from "docker run" cmd-line
export HCP_ATTESTCLIENT_TPM2TOOLS_TCTI
export HCP_ATTESTCLIENT_ATTEST_URL

echo "Running 'attestclient'"

# We store some stuff we should cleanup, so use a trap
tmp_pcrread=`mktemp`
tmp_secrets=`mktemp`
tmp_attest=`mktemp`
tmp_key=`mktemp`
tmp_extract=`mktemp -d`
trap 'rm -rf $tmp_pcrread $tmp_secrets $tmp_attest $tmp_key $tmp_extract' EXIT ERR

# Check that our TPM is configured and alive
waitcount=0
until tpm2_pcrread >> "$tmp_pcrread" 2>&1; do
	waitcount=$((waitcount+1))
	if [[ $waitcount -eq 1 ]]; then
		echo "Warning: waiting for TPM to initialize" >&2
	fi
	if [[ $waitcount -eq 11 ]]; then
		echo "Error: giving up. Outputs of tpm_pcrread follow;" >&2
		cat $tmp_pcrread >&2
		exit 1
	fi
	sleep 1
done
if [[ $waitcount -gt 0 ]]; then
	echo "Info: TPM available after retrying" >&2
fi

# TODO: this is a temporary and bad fix. The swtpm assumes that connections
# that are set up (tpm2_startup) but not gracefully terminated (tpm2_shutdown)
# are suspicious, and if it happens enough (3 or 4 times, it seems) the TPM
# locks itself to protect against possible dictionary attack. However our
# attestclient is calling a high-level util ("tpm2-attest attest"), so it is
# not clear where tpm2_startup is happening, and it is even less clear where to
# add a matching tpm2_shutdown. Instead, we rely on the swtpm having non-zero
# tolerance to preceed each run of the attestclient (after it has already
# failed at least once to call tpm2_shutdown), and we also rely on there being
# no dictionary policy in place to prevent us from simply resetting the
# suspicion counter!! On proper TPMs (e.g. GCE vTPM), this dictionarylockout
# call will actually fail so has to be commented out.
tpm2_dictionarylockout --clear-lockout

# Now keep trying to get a successful attestation. It may take a few seconds
# for our TPM enrollment to propagate to the attestation server, so it's normal
# for this to fail a couple of times before succeeding.
waitcount=0
wait_tens=2
until ./sbin/tpm2-attest attest $HCP_ATTESTCLIENT_ATTEST_URL \
				> $tmp_secrets 2>> "$tmp_attest"; do
	waitcount=$((waitcount+1))
	if [[ $waitcount -eq 1 ]]; then
		echo "Warning: attestation failed, may just be replication latency" >&2
	fi
	if [[ $waitcount -eq 11 ]]; then
		if [[ $wait_tens -eq 1 ]]; then
			echo "Error: attestation failed many times, giving up" >&2
			cat $tmp_attest >&2
			exit 1
		fi
		wait_tens=$((wait_tens-1))
		echo "Warning: retried for another 10 seconds" >&2
		waitcount=1
	fi
	sleep 1
done
echo "Info: attestation succeeded after retrying" >&2

if (
	echo "Extracting the attestation result"
	tar xvf $tmp_secrets -C $tmp_extract
	echo "Signature-checking the received assets"
	./sbin/tpm2-attest verify-unsealed $tmp_extract > /dev/null
	cd $tmp_extract
	MYSEALED=$(ls -1 *.symkeyenc | sed -e "s/.symkeyenc\$//")
	for i in $MYSEALED; do
		if [[ ! -f "$i.policy" || ! -f "$i.enc" ]]; then
			echo "Warning, asset '$i' missing attributes" >&2
			continue
		fi
		echo "Unsealing asset '$i'"
		rm $tmp_key
		tpm2-recv "$i.symkeyenc" $tmp_key \
			tpm2 policypcr '--pcr-list=sha256:11' > /dev/null 2>&1
		aead_decrypt "$i.enc" $tmp_key "$i"
	done
	if [[ -n $HCP_ATTESTCLIENT_CALLBACK ]]; then
		echo "Running callback '$HCP_ATTESTCLIENT_CALLBACK'"
		(exec $HCP_ATTESTCLIENT_CALLBACK)
	fi
); then
	echo "Success!"
else
	echo "Error of some kind."
	echo "Leaving tarball: $tmp_secrets"
	echo "Leaving extraction: $tmp_extract"
	tmp_secrets=""
	tpm_extract=""
fi
