#!/bin/bash

[[ -z $PS1 ]] && set -e

# This script encapsulates the logic for;
# dname2tar - pulling a container image from the docker daemon as a tarball,
# tar2ext4 - creating a bootable ext4 image from such a tarball (requires sudo
#            privs for mount/tar/umount).
# tar2img - creating a bootable disk image from such a tarball (requires sudo
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
#
# TODO: we shouldn't even presume to get loop0 in the bootstrap VM, but
# definitely shouldn't make such an assumption on the host. Fix the losetup
# handling!

dname2tar()
{
	myimg=$1
	mytar=$2
	echo "Extracting '$myimg' container image as a tarball" >&2
	(
	tmpfp=$(mktemp)
	tmpd=$(mktemp -d)
	trap 'rm -f $tmpfp ; rm -rf $tmpd' EXIT
	(
	trap 'rm -f $mytar' ERR
	tmpf=$(basename $tmpfp)
	CID=$(docker create --name $tmpf $myimg)
	docker export -o "$mytar" $CID
	docker container rm $CID
	cd $tmpd
	mkdir etc
	cat > etc/hosts <<EOF
127.0.0.1 localhost
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
	ln -sf /run/systemd/resolve/stub-resolv.conf etc/resolv.conf
	tar -uf "$mytar" etc/hosts etc/resolv.conf
	)
	)
}

tar2ext4()
{
	mytar=$1
	myext4=$2
	mymegs=$3
	(
	trap 'rm -f "$myext4" "$myext4.isok"' ERR
	dd if=/dev/zero of=$myext4 bs=1048576 count=$mymegs
	/sbin/mkfs.ext4 -F $myext4
	if [[ -f $BOOTSTRAP_IMG ]]; then
		echo "hcp_mkext4.sh tar2img -> relaying into a UML VM" >&2
		img_dir=$(dirname "$myext4")
		img_name=$(basename "$myext4")
		rm -f "$myext4.isok"
		cmd="mkdir /wibble && "
		cmd+="mount -t auto /mnt/uml-command/output_ext4/$img_name /wibble && "
		cmd+="tar -xf /mnt/uml-command/input.tar -C /wibble > /dev/null 2>&1 && "
		cmd+="umount /wibble && "
		cmd+="touch /mnt/uml-command/output_ext4/$img_name.isok"
		docker run --rm --tmpfs /dev/shm:exec \
			-v $BOOTSTRAP_IMG:/rootfs.ext4:ro \
			-v $mytar:/mnt/uml-command/input.tar:ro \
			-v $img_dir:/mnt/uml-command/output_ext4 \
			$BOOTSTRAP_DNAME \
			/start.sh \
			bash -c "$cmd"
		if [[ ! -f "$myext4.isok" ]]; then
			echo "Error, invoking UML to build ext4 failed" >&2
			exit 1
		fi
		rm -f "$myext4.isok"
	else
		echo "Converting tarball to ext4 image" >&2
		(
		mymount=$(mktemp -d)
		trap 'umount $mymount > /dev/null 2>&1 || true; rm -rf $mymount' EXIT
		cmd="mount -t auto $myext4 $mymount && "
		cmd+="tar -xf $mytar -C $mymount > /dev/null 2>&1 && "
		cmd+="umount $mymount"
		sudo bash -c "$cmd"
		)
	fi
	)
}

tar2img()
{
	mytar=$1
	myimg=$2
	mymegs=$3
	(
	trap 'rm -f $myimg' ERR
	if [[ -n $BOOTSTRAP_IMG ]]; then
		echo "hcp_mkext4.sh tar2img -> relaying into a UML VM" >&2
		docker run --rm --tmpfs /dev/shm:exec \
			-v $BOOTSTRAP_IMG:/rootfs.ext4:ro \
			-v $mytar:/mnt/uml-command/input.tar:ro \
			-v $myimg:/mnt/uml-command/output_img \
			$BOOTSTRAP_DNAME \
			/start.sh \
			/hcp_mkext4.sh tar2img \
				/mnt/uml-command/input.tar \
				/mnt/uml-command/output_img \
				$mymegs \
				/mnt/foo
	else
		echo "Converting tarball to disk image" >&2
		(
		mymount=$(mktemp -d)
		trap '[[ $done_losetup -eq 0 ]] || losetup -d /dev/loop;
			umount $mymount > /dev/null 2>&1 || true;
			rmdir $mymount > /dev/null 2>&1 || true' EXIT
		dd if=/dev/zero of=$myimg/disk bs=1048576 count=$mymegs
		sfdisk $myimg/disk <<EOF
label: dos
label-id: 0xabbaf00d
device: wibble.img
unit: sectors

wibble.img : start=2048, type=83, bootable
EOF
		losetup -o 1048576 /dev/loop0 $myimg/disk
		mkfs.ext4 /dev/loop0
		mount -t auto /dev/loop0 $mymount
		tar -xf $mytar -C $mymount > /dev/null 2>&1
		extlinux --install $mymount/boot/ > /dev/null 2>&1
		cat > $mymount/boot/syslinux.cfg <<EOF
DEFAULT linux
  SAY Now booting the kernel from SYSLINUX...
 LABEL linux
  KERNEL /vmlinuz
  APPEND ro root=/dev/sda1 initrd=/initrd.img
EOF
		dd if=/usr/lib/syslinux/mbr/mbr.bin of=$myimg/disk bs=440 count=1 conv=notrunc
		cp $mymount/vmlinuz $myimg/vmlinuz
		cp $mymount/initrd.img $myimg/initrd.img
		)
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
	echo "    tar2img - convert tarball to bootable disk image" $x
	echo "        \$1 - path to tarball" $x
	echo "        \$2 - output path for the disk image" $x
	echo "        \$3 - size of the disk image (in 'dd' language)" $x
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
	tar2img)
		tar2img "$@"
		;;
	*)
		usage
		;;
esac
