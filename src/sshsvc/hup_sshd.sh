#!/bin/bash

SSHDPID=$(cat /var/run/sshd.pid)
kill -HUP $SSHDPID
echo "hup_sshd.pid: just HUP'd sshd ($PID)" >&2
