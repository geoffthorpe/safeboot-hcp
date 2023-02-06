#!/bin/bash

# This script exists to handle the launching of UML in such a way that;
# (a) the "/init.sh" script runs in the VM
# (b) arguments to this script become arguments to that script
#
# Perhaps overkill, but I'll encode the arguments as a JSON list into a
# temporary file and share that with the VM. Bash, whitespace, erk.

if [[ ! -d /mnt/uml-command ]]; then
	mkdir /mnt/uml-command
elif [[ -f /mnt/uml-command/args.json ]]; then
	rm /mnt/uml-command/args.json
fi

trap 'rm /mnt/uml-command/args.json' EXIT

if [[ $# -eq 0 || ( $# -eq 1 && ( $1 == "bash" || $1 == "/bin/bash" ) ) ]]; then
	be_interactive=1
else
	be_interactive=0
fi

(
# TODO: there is probably a better way of doing this via 'jq'
echo -n "["
needcomma=
while :; do
	if [[ $# == 0 ]]; then
		break
	fi
	if [[ -z $needcomma ]]; then
		needcomma=1
	else
		echo -n ","
	fi
	# Encode $1 as a JSON string.
	# - escape characters \ and "
	# - wrap the string in quotes
	echo -n "$1" | sed -e 's,\\,\\\\,g' | sed -e 's,",\\",g' | sed -e 's,^.*$,"&",'
	shift
done
echo "]"
) > /mnt/uml-command/args.json

# TODO: get COW working with UML again. It should be possible to pass
# "ubd0=/foo.cow,/rootfs.ext4" to the kernel and have foo.cow be created
# automatically. Until then, we're simply making an ephemeral copy of
# rootfs.ext4, which is more slower/pricier.
if [[ -f /foo.ext4 ]]; then
	rm /foo.ext4
fi
cp /rootfs.ext4 /foo.ext4

# TODO: there is currently no stdout/stderr - all the console output goes to
# stdout for this command. So for the UML container tool to be usable for
# running commands and capturing output (from /init.sh and whatever it spawns),
# we need to ensure there's no kernel output mingled into it. By passing
# "quiet" we get rid of nearly everything, all that remains is the "reboot:
# System halted" message at the end. This is why we do the oddball
# piped-buffering thing via suppress_reboot_output().
suppress_reboot_output()
{
	haveline=0
	lastline=""
	eof=0
	while :; do
		if ! read; then
			eof=1
		fi
		if [[ $haveline -ne 0 && ( $eof -eq 0 || \
				$lastline != "reboot: System halted" ) ]]; then
			echo "$lastline"
		fi
		if [[ $eof -ne 0 ]]; then
			break
		fi
		haveline=1
		lastline=$REPLY
	done
}
cmd="/linux ubd0=/foo.ext4 root=/dev/ubda rw hostfs=/mnt/uml-command"
cmd="$cmd mem=2G quiet init=/init.sh"
if [[ $be_interactive -eq 0 ]]; then
	$cmd | suppress_reboot_output
else
	$cmd
fi
