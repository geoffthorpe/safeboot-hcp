#!/bin/bash

[[ -z $PS1 ]] && set -e

# This script encapsulates the logic for;
# dname2tar - pulling a container image from the docker daemon as a tarball,
# tar2ext4 - creating a bootable ext4 image from such a tarball (requires sudo
#            privs for mount/tar/umount).
#
# This logic was previously in the Makefile recipes directly, but they have
# been suctioned out into this script for one reason in particular;
#
# To perform the tarball -> bootable image step requires root privileges (at
# least with the current tooling). But the next time you need to do this, you
# shouldn't need root privileges _on the host_, because you can use the
# previous bootable image to run a VM, which doesn't require root privileges,
# and then you can do your privilege-requiring manipulations _inside_ the VM.
# In other words, you can avoid needing elevated privileges to build and run
# everything, so long as you already have a cached/old/general-purpose bootable
# image lying around to help with bootstrapping.
#
# So ... this script takes care of pivoting between the normal case (we work on
# the host and need sudo privs to construct bootable images) and the
# bootstrapped case (we start a VM and construct the bootable images inside
# it).
#
# Note, the dname2tar routine requires no privileges and so there is no good
# reason to do this inside a VM (which requires forwarding the docker socket,
# having docker tools inside the VM, etc).
#
# Note, we use subshells and traps. This isn't to ensure a clean transactional
# "rollback" if something goes wrong, so if we fail to kill a container or
# remove a tempfile, tough. However it does try to ensure that you don't have
# an output file if something goes wrong, because a subsequent run of "make"
# may skip the step that failed if it sees the presence of an output file with
# a recent timestamp.

dname2tar()
{
	myimg=$1
	mytar=$2
	echo "Extracting '$myimg' container image as a tarball" >&2
	(
	trap 'rm -f $mytar' ERR
	tmpfp=$(mktemp)
	tmpf=$(basename $tmpfp)
	CID=$(docker create --name $tmpf $myimg)
	docker export -o "$mytar" $CID
	docker container rm $CID
	rm $tmpfp
	)
}

tar2ext4()
{
	mytar=$1
	myext4=$2
	mysz=$3
	mymount=$4
	echo "Converting tarball to ext4 image" >&2
	(
	trap 'rm -f $myext4' ERR
	dd if=/dev/zero of=$myext4 bs=$mysz count=1
	/sbin/mkfs.ext4 -F $myext4
	if [[ -n $BOOTSTRAP_IMG ]]; then
		img_dir=$(dirname "$myext4")
		img_name=$(basename "$myext4")
		cmd="mkdir /wibble && "
		cmd+="mount -t auto /mnt/uml-command/output_ext4/$img_name /wibble && "
		cmd+="tar -xf /mnt/uml-command/input.tar -C /wibble && "
		cmd+="umount /wibble"
		docker run --rm --tmpfs /dev/shm:exec \
			-v $BOOTSTRAP_IMG:/rootfs.ext4:ro \
			-v $mytar:/mnt/uml-command/input.tar:ro \
			-v $img_dir:/mnt/uml-command/output_ext4 \
			$BOOTSTRAP_DNAME \
			/start.sh \
			bash -c "$cmd"
	else
		cmd="mount -t auto $myext4 $mymount && "
		cmd+="tar -xf $mytar -C $mymount && "
		cmd+="umount $mymount"
		sudo bash -c "$cmd"
	fi
	)
}

usage()
{
	x=">&2"
	echo "Usage: hcp_mkext4 <cmd> [args...]" $x
	echo "Where <cmd> is;" $x
	echo "    dname2tar - extract container image into a tarball" $x
	echo "        \$1 - docker image name" $x
	echo "        \$2 - output path for the tarball" $x
	echo "    tar2ext4 - convert tarball to bootable ext4 image" $x
	echo "        \$1 - path to tarball" $x
	echo "        \$2 - output path for the ext4 image" $x
	echo "        \$3 - size of the ext4 image (in 'dd' language)" $x
	echo "        \$4 - path to a directory to use for temporary mount" $x
	exit -1
}

# Command-line argument parsing
[[ $# -gt 0 ]] || usage -1
cmd=$1
shift

case $cmd in
	dname2tar)
		dname2tar "$@"
		;;
	tar2ext4)
		tar2ext4 "$@"
		;;
	*)
		usage
		;;
esac
