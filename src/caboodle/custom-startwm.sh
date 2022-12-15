#!/bin/bash

log "Inside custom-startwm.sh"

# We assume that code running as root, before dropping privs to run this code,
# had saved the environment we will need here;
source $HOME/hcp.env

source /hcp/common/hcp.sh

/startpulse.sh &

if [[ -f $HOME/.hcp/pkinit/user-key.pem ]]; then
	kinit -C FILE:$HOME/.hcp/pkinit/user-key.pem $USER /orig-chosen-wm
else
	/orig-chosen-wm
fi
