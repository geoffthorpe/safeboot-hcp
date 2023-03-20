#!/bin/bash

source /hcp/sshsvc/common.sh

if [[ ! -f $HCP_SSHSVC_GLOBAL_INIT ]]; then
	echo "Error, setup_local.sh being run before setup_global.sh" >&2
	exit 1
fi

if [[ -f "$HCP_SSHSVC_LOCAL_INIT" ]]; then
	echo "Error, setup_local.sh being run but already initialized" >&2
	exit 1
fi

echo "Initializing (rootfs-local) sshsvc state"

# sshd expects this directory to exist. TODO: can this be scoped to
# $HCP_SSHSVC_ETC? If we end up trying to run multiple sshsvc instances
# co-tenant, we might right into trouble with collisions on this.
mkdir -p /run/sshd
chmod 755 /run/sshd

# Done!
touch "$HCP_SSHSVC_LOCAL_INIT"
