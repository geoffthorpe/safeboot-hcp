#!/bin/bash

log "Inside custom-startwm.sh"

source /hcp/common/hcp.sh

/startpulse.sh &

# We assume (because of the current 'webtop' from linuxserver.io) that we're 'abc'
# in the current environment and have a cred to log in (to 'sherver') as 'luser'.
if [[ -f $HOME/.hcp/pkinit/user-luser-key.pem ]]; then
	kinit -C FILE:$HOME/.hcp/pkinit/user-luser-key.pem luser /orig-chosen-wm
else
	/orig-chosen-wm
fi
