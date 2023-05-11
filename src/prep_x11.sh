#!/bin/bash

ENVFILE=$1

if [[ ! -d output || ! -d src/hcp ]]; then
	echo >&2 "Error, not running from top-level directory"
	exit 1
fi

if [[ -z $DISPLAY ]]; then
	echo >&2 "Error, DISPLAY not defined"
	exit 1
fi

if [[ -n $XAUTHORITY ]]; then
	if [[ ! -f $XAUTHORITY ]]; then
		echo >&2 "Error, XAUTHORITY ($XAUTHORITY) missing"
		exit 1
	fi
elif [[ -f ~/.Xauthority ]]; then
	XAUTHORITY=~/.Xauthority
else
	XAUTHORITY=output/docker-compose.tmpX11/Xauthority
fi
echo "XAUTHORITY=$XAUTHORITY" >> $ENVFILE

xauth nlist $DISPLAY |
while :; do
	read s
	k=$(echo "$s" | sed -e "s/^.* //")
	echo "XAUTHKEY=$k" >> $ENVFILE
	break
done
