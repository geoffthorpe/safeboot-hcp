#!/bin/bash

source /hcp/common/hcp.sh

retries=0
pause=1
VERBOSE=0
URL="$HCP_ATTESTCLIENT_ATTEST_URL"
TCTI="$HCP_ATTESTCLIENT_TPM2TOOLS_TCTI"
ANCHOR=$([[ -f /enrollverifier/key.pem ]] &&
	echo "/enrollverifier/key.pem" || true)
CALLBACKS="$HCP_ATTESTCLIENT_CALLBACKS"

usage() {
	((${1:-1} == 0)) || exec 1>&2
	pager=cat
	if [[ -t 0 && -t 1 && -t 2 ]]; then
		if [[ -z ${PAGER:-} ]] && type less >/dev/null 2>&1; then
			pager=less
		elif [[ -z ${PAGER:-} ]] && type more >/dev/null 2>&1; then
			pager=more
		elif [[ -n ${PAGER:-} ]]; then
			pager=$PAGER
		fi
	fi
	$pager <<EOF
Usage: $PROG [OPTIONS] [names ...]

  Runs the attestation client. Note that the TPM must be available when this
  tool runs - the retry logic (per -R and -P options) only applies to the
  attestation process, to support the case where the TPM/host tuple has been
  enrolled but the enrollment has not yet replicated to the attestation
  service.

  Options:

    -h               This message
    -v               Verbose
    -R <num>         Number of retries before failure
        (default: $retries)
    -P <seconds>     Time between retries
        (default: $pause)
    -U <url>         Attestation URL
        (default: $(test -n "$URL" && echo "$URL" || echo "None"))
    -T <tcti>        'TPM2TOOLS_TCTI' setting, for path to TPM
        (default: $(test -n "$TCTI" && echo "$TCTI" || echo "None"))
    -A <path>        Path to enrollsvc trust anchor for verification
        (default: $(test -n "$ANCHOR" && echo "$ANCHOR" || echo "None"))
    -C <callbacks>   Space-separated list of callbacks to execute"
        (default: $(test -n "$CALLBACKS" && echo "\"$CALLBACKS\"" || echo "None"))
EOF
	exit "${1:-1}"
}

while getopts +:R:P:U:T:A:C:hv opt; do
case "$opt" in
R)	retries="$OPTARG";;
P)	pause="$OPTARG";;
U)	URL="$OPTARG";;
T)	TCTI="$OPTARG";;
A)	ANCHOR="$OPTARG";;
C)	CALLBACKS="$OPTARG";;
h)	usage 0;;
v)	((VERBOSE++)) || true;;
*)	echo >&2 "Unknown option: $opt"; usage;;
esac
done
shift $((OPTIND - 1))

if ((VERBOSE > 0)); then
	cat >&2 <<EOF
Starting $PROG:
 - retries=$retries
 - pause=$pause
 - onlyenroll=$onlyenroll
 - onlycreate=$onlycreate
 - VERBOSE=$VERBOSE
 - URL=$URL
 - JSONPATH=$JSONPATH
 - #names=$#
 - {names}=$@
EOF
fi

if [[ -z $URL ]]; then
	echo "Error, no attestation URL configured" >&2
	exit 1
fi
if [[ -z $TCTI ]]; then
	echo "Error, no TCTI (path to TPM) configured" >&2
	exit 1
fi
export TPM2TOOLS_TCTI="$TCTI"
if [[ -z $ANCHOR ]]; then
	echo "Error, no trust anchor (enrollsvc signer cert) configured" >&2
	exit 1
fi
export ENROLL_SIGN_ANCHOR=$ANCHOR

source_safeboot_functions

# The following helps to convince the safeboot scripts to find safeboot.conf
# and functions.sh
export DIR=/install-safeboot
cd $DIR

echo "Running 'attestclient'"

# We store some stuff we should cleanup, so use a trap
tmp_pcrread=`mktemp`
tmp_secrets=`mktemp`
tmp_attest=`mktemp`
tmp_key=`mktemp`
tmp_extract=`mktemp -d`
trap 'rm -rf $tmp_pcrread $tmp_secrets $tmp_attest $tmp_key $tmp_extract' EXIT ERR

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

while :; do
	ecode=0
	# "tpm2-attest attest" returns an exit code of 2 (rather than 1) if the
	# error was (only) that the server didn't have an enrollment matching
	# out TPM. This is the case where retry logic applies. Note, we
	# replicate the semantic - if we fail because the exit codes are 2,
	# we'll exit with 2 as well.
	./sbin/tpm2-attest attest $URL > "$tmp_secrets" 2> "$tmp_attest" ||
		ecode=$?
	if [[ $ecode == 2 ]]; then
		if [[ $retries == 0 ]]; then
			echo "Error, attestsvc doesn't recognize our TPM" >&2
			exit 2
		fi
		((VERBOSE > 0)) &&
			echo "Warn, attestsvc doesn't (yet) recognize our TPM" >&2
		retries=$((retries-1))
		sleep $pause
		continue
	fi
	if [[ $ecode != 0 ]]; then
		echo "Error, 'tpm2-attest attest' failed;" >&2
		cat "$tmp_attest" >&2
		exit 1
	fi
	echo "Info, 'tpm2-attest attest' succeeded"
	break
done

if ! (
	echo "Extracting the attestation result"
	tar xvf $tmp_secrets -C $tmp_extract | sort
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
	if [[ -n $CALLBACKS ]]; then
		for i in $CALLBACKS; do
			echo "Running callback '$i'"
			if ! $i; then
				echo "Failure in callback '$i'" >&2
				exit 1
			fi
		done
	fi
); then
	echo "Error of some kind."
	echo "Leaving tarball: $tmp_secrets"
	echo "Leaving extraction: $tmp_extract"
	tmp_secrets=""
	tmp_extract=""
	exit 1
fi
