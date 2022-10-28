#!/bin/bash

source /hcp/common/hcp.sh

retries=0
pause=1
VERBOSE=0
FQDN=${HCP_HOSTNAME}.${HCP_FQDN_DEFAULT_DOMAIN}
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

  We ssh to ourselves, using a PKI cred to get a TGT that authenticates via
  GSSAPI. This is used to determine if the service is alive, e.g. if a startup
  script needs to wait for the service to come up before initializing and, once
  it has, will treat any subsequent error as fatal.

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

tout=
terr=
onexit() {
	((VERBOSE > 0)) && echo >&2 "In trap handler, removing temp files"
	rm -f "$tout" "$terr"
}
trap onexit EXIT
tout=$(mktemp)
terr=$(mktemp)

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
	((VERBOSE > 0)) && echo >&2 "Running: ssh-keyscan $FQDN > $myknownhosts"
	res=0
	ssh-keyscan $FQDN > $tout 2> $terr || res=$?
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
