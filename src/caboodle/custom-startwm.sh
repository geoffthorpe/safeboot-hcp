#!/bin/bash

source /hcp/common/hcp.sh

/startpulse.sh &

if [[ -f $HOME/.hcp/pkinit/user-key.pem ]]; then
	kinit -C FILE:$HOME/.hcp/pkinit/user-key.pem $USER /orig-chosen-wm
else
	/orig-chosen-wm
fi
