#!/bin/bash

set -e

[[ -z $V ]] || echo "CHOWNER, running in $2, using reference=$1"

MYUID=$(stat --format=%u $1)
MYGID=$(stat --format=%g $1)

if [[ -z $V ]]; then
	find $2 ! -uid $MYUID -exec chown -h $MYUID:$MYGID {} \;
else
	echo "UID=$MYUID"
	echo "GID=$MYGID"
	find $2 ! -uid $MYUID -exec chown -h -v $MYUID:$MYGID {} \;
fi
