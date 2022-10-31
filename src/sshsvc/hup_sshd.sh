#!/bin/bash

if SSHDPID=$(cat /var/run/sshd.pid 2>/dev/null); then
	kill -HUP $SSHDPID
	echo "hup_sshd.pid: just HUP'd sshd ($PID)" >&2
fi
