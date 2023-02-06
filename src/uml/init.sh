#!/bin/bash

# This script is used as the "init=" argument to the UML kernel. It's purpose
# is to run whatever the user had asked for, and trigger the 'myshutdown' tool
# once that exits. It also takes care of some minimal initialisation;

trap '/myshutdown' EXIT

mount -t proc proc /proc/
mount -t sysfs sys /sys/

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
