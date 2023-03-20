#!/bin/bash

# This script is used as the "init=" argument to the UML kernel when running a
# UML "bootstrap" image. It's purpose is to handle UML-specific initialization
# (/proc, /sys, dhcp, swap) then parse the input arguments, run what the user
# asked for, then trigger the 'myshutdown' which unceremonially halts the VM.
#
# This is not for running HCP workloads - because there is no JSON config to
# pass to the launcher. It is simply a conduit for running arbitrary shell
# commands inside a barely-booted kernel, and then shutting the kernel down.
# Eg. there's no systemd or any other service initialization - this script _is_
# the "init" process that the kernel runs in PID 1. This is used to build
# filesystem and disk images, without requiring special privileges on the host
# (eg. mount, losetup, ...).

set -e

# Whatever happens, try to (a) convey success/failure to the caller (they will
# look at the 'exitcode' file post-VM-destruction), and (b) shutdown the
# kernel, so that control does indeed return to the caller.
on_exit()
{
	echo $? > /mnt/uml-command/exitcode
	/myshutdown
}
trap 'on_exit' EXIT

# Minimal setup of VM environment
mount -t proc proc /proc/
mount -t sysfs sys /sys/
dhclient eth0
mkswap /dev/ubdb
swapon /dev/ubdb

# The outside passes a "uml-command" mount to us, with instructions in it
mkdir -p /mnt/uml-command
mount -t hostfs none /mnt/uml-command
numargs=$(cat /mnt/uml-command/args.json | jq -r '. | length')
if [[ $numargs -eq 0 ]]; then
	cmd=/bin/bash
else
	loop=0
	cmd=""
	while [[ $numargs -gt $loop ]]; do
		item=$(cat /mnt/uml-command/args.json | jq -r ".[$loop]")
		# item has been unescaped (from the JSON) so needs to be
		# rescaped (for bash)
		item=$(echo "$item" | sed -e 's,\\,\\\\,g' | sed -e 's,",\\",g')
		if [[ $loop -eq 0 ]]; then
			cmd="\"$item\""
		else
			cmd="$cmd \"$item\""
		fi
		loop=$((loop+1))
	done
fi

bash -c "$cmd"
