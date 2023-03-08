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

# Start up a VDE switch
vde_switch -d -s /vdeswitch -M /vdeswitch_mgmt

# Plug a 'slirpvde' into the switch, it will provide DHCP, DNS, and act as
# a gateway to host networking.
# TODO: need to make this configurable;
# - "--host" argument to stipulate what network addresses to use (to avoid
#   conflicting with other networks the host cares about).
# - "-L/-U" for opening access to the VM (like "--publish" for docker)
slirpvde --daemon --dhcp /vdeswitch

# TODO: there is currently no stdout/stderr - all the console output goes to
# stdout for this command. So for the UML container tool to be usable for
# running commands and capturing output (from /init.sh and whatever it spawns),
# we need to ensure stdout/stderr are split, or stderr suppressed entirely. By
# passing "quiet" we get rid of nearly everything, all that remains is the
# "reboot: System halted" message at the end. But this is fragile, some other
# spurious bad luck or corner case might trigger stderr output that would slip
# through.
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
# Create a throw-away swap file
dd if=/dev/zero of=/tmp.swapfile count=4 bs=1G
cmd="/linux ubd0=/foo.ext4 ubd1=/tmp.swapfile root=/dev/ubda rw hostfs=/mnt/uml-command"
cmd="$cmd eth0=vde,/vdeswitch"
if [[ -z $VERBOSE || $VERBOSE == 0 ]]; then
	cmd="$cmd quiet"
fi
cmd="$cmd mem=4G init=/init.sh"
if [[ -n $VERBOSE && $VERBOSE -gt 0 ]]; then
	echo "About to run: $cmd" >&2
fi
if [[ $be_interactive -eq 0 ]]; then
	$cmd | suppress_reboot_output
else
	$cmd
fi
if [[ -f /mnt/uml-command/exitcode ]]; then
	exitcode=$(cat /mnt/uml-command/exitcode)
	exit $exitcode
fi
exit 0
