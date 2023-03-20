#!/bin/bash

source /hcp/common/hcp.sh

export HCP_SWTPMSVC_STATE=$(hcp_config_extract ".swtpmsvc.state")
export HCP_SWTPMSVC_SOCKDIR=$(hcp_config_extract_or ".swtpmsvc.sockdir" "")
export HCP_SWTPMSVC_TPMSOCKET="$HCP_SWTPMSVC_SOCKDIR/tpm"

retries=0
pause=1
VERBOSE=0
TPM2TOOLS_TCTI=swtpm:path=$HCP_SWTPMSVC_TPMSOCKET

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
Usage: $PROG [OPTIONS]

  Tests whether the given TPM instance responds to a basic query, as a
  healthcheck.

  Options:

    -h               This message
    -v               Verbose
    -R <num>         Number of retries before failure
        (default: $retries)
    -P <seconds>     Time between retries
        (default: $pause)
    -T <tcti>        TCTI (for tpm2-tss) string, path to TPM
        (default: $TPM2TOOLS_TCTI)

EOF
	exit "${1:-1}"
}

while getopts +:R:P:T:hv opt; do
case "$opt" in
R)	retries="$OPTARG";;
P)	pause="$OPTARG";;
T)	TPM2TOOLS_TCTI="$OPTARG";;
h)	usage 0;;
v)	((VERBOSE++)) || true;;
*)	echo >&2 "Unknown option: $opt"; usage;;
esac
done
shift $((OPTIND - 1))
(($# == 0)) || (echo 2> "Unexpected options: $@" && exit 1) || usage

tout=$(mktemp)
terr=$(mktemp)
onexit() {
	((VERBOSE > 0)) && echo >&2 "In trap handler, removing temp files"
	rm -f "$tout" "$terr"
}
trap onexit EXIT

if ((VERBOSE > 0)); then
	cat >&2 <<EOF
Starting $PROG:
 - retries=$retries
 - pause=$pause
 - VERBOSE=$VERBOSE
 - TPM2TOOLS_TCTI=$TPM2TOOLS_TCTI
 - Temp stdout=$tout
 - Temp stderr=$terr
EOF
fi

export TPM2TOOLS_TCTI

while :; do
	((VERBOSE > 0)) && echo >&2 "Running: tpm2_pcrread (TCTI=$TPM2TOOLS_TCTI)"
	res=0
	tpm2_pcrread >$tout 2>$terr || res=$?
	if [[ $res == 0 ]]; then
		((VERBOSE > 0)) && echo >&2 "Success"
		exit 0
	fi
	((VERBOSE > 0)) && echo >&2 "Failed with code: $res"
	((VERBOSE > 1)) && echo >&2 "Error output:" && cat >&2 "$terr"
	if [[ $retries == 0 ]]; then
		echo >&2 "Failure, giving up"
		exit $res
	fi
	((retries--))
	((VERBOSE > 0)) && echo >&2 "Pausing for $pause seconds"
	sleep $pause
done
