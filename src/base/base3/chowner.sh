#!/bin/bash

set -e

if [[ $# -lt 2 ]]; then
	echo "Error, no paths to chown" >&2
	exit 1
fi

REFFILE=$1
shift
[[ -z $V ]] || echo "CHOWNER, using reference=$REFFILE"
MYUID=$(stat --format=%u $REFFILE)
MYGID=$(stat --format=%g $REFFILE)
[[ -z $V ]] || (echo "UID=$MYUID" && echo "GID=$MYGID")
XTRA=
[[ -z $V ]] || XTRA=-v

while [[ $# -gt 0 ]]; do
	[[ -z $V ]] || echo "CHOWNER, path: $1"
	find $1 ! -uid $MYUID -exec chown -h $XTRA $MYUID:$MYGID {} \;
	shift
done
