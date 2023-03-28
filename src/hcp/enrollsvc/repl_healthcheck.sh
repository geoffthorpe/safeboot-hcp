#!/bin/bash

source /hcp/common/hcp.sh

retries=0
pause=1
VERBOSE=0

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

EOF
	exit "${1:-1}"
}

while getopts +:R:P:hv opt; do
case "$opt" in
R)	retries="$OPTARG";;
P)	pause="$OPTARG";;
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
 - Temp stdout=$tout
 - Temp stderr=$terr
EOF
fi

while :; do
	((VERBOSE > 0)) && echo >&2 "Running: git ls-remote --heads"
	res=0
	git ls-remote --heads git://localhost/enrolldb >$tout 2>$terr || res=$?
	if [[ $res == 0 ]]; then
		((VERBOSE > 0)) && echo >&2 "Success"
		exit 0
	fi
	((VERBOSE > 1)) && echo >&2 "Failed with code: $res"
	((VERBOSE > 2)) && echo >&2 "Error output:" && cat >&2 "$terr"
	if [[ $retries == 0 ]]; then
		echo >&2 "Failure, giving up"
		exit $res
	fi
	((retries--))
	((VERBOSE > 2)) && echo >&2 "Pausing for $pause seconds"
	sleep $pause
done
