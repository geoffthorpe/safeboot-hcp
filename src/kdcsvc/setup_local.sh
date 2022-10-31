#!/bin/bash

source /hcp/kdcsvc/common.sh

if [[ ! -f $HCP_KDCSVC_GLOBAL_INIT ]]; then
	echo "Error, setup_local.sh being run before setup_global.sh" >&2
	exit 1
fi

if [[ -f "$HCP_KDCSVC_LOCAL_INIT" ]]; then
	echo "Error, setup_local.sh being run but already initialized" >&2
	exit 1
fi

echo "Initializing (rootfs-local) kdcsvc state"

# Create any symlinks in the rootfs that are expected
if ! ln -s "$HCP_KDCSVC_STATE/etc/sudoers" /etc/sudoers.d/hcp > /dev/null 2>&1 && \
		[[ ! -h /etc/sudoers.d/hcp ]]; then
	echo "Error, couldn't create symlink '/etc/sudoers.d/hcp'" >&2
	exit 1
fi
if [[ $HCP_KDCSVC_STATE != /kdc ]] &&
		! ln -s "$HCP_KDC_STATE" /kdc > /dev/null 2>&1; then
	echo "Error, couldn't ensure /kdc exists" >&2
	exit 1
fi

# When a web handler (in mgmt_api.py, running as "www-data") runs 'sudo
# do_kadmin', we inhibit any transfer of environment through the sudo barrier
# as we want to protect against a compromised web app. So run_kdc.sh stores the
# environment at startup time, so that do_kadmin has a known-good source.
export_hcp_env > /root/exported.hcp.env
echo "export PATH=$PATH" >> /root/exported.hcp.env
echo "export LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >> /root/exported.hcp.env

# Done!
touch "$HCP_KDCSVC_LOCAL_INIT"
echo "Local state now initialized"
