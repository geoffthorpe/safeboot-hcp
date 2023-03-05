#!/bin/bash

source /hcp/enrollsvc/common.sh

expect_root

if [[ ! -f $HCP_ENROLLSVC_GLOBAL_INIT ]]; then
	echo "Error, setup_local.sh being run before setup_global.sh" >&2
	exit 1
fi

if [[ -f "$HCP_ENROLLSVC_LOCAL_INIT" ]]; then
	echo "Error, setup_local.sh being run but already initialized" >&2
	exit 1
fi

echo "Initializing (rootfs-local) enrollsvc state"

# Copy creds to the home dir if we have them and they aren't copied yet
if [[ -d /enrollsigner && ! -d "$SIGNING_KEY_DIR" ]]; then
	echo "Copying asset-signing creds to '$SIGNING_KEY_DIR'"
	cp -r /enrollsigner $SIGNING_KEY_DIR
	chown -R $HCP_ENROLLSVC_USER_DB $SIGNING_KEY_DIR
	if [[ ! -f $SIGNING_KEY_PUB || ! -f $SIGNING_KEY_PRIV ]]; then
		echo "Error, SIGNING_KEY_{PUB,PRIV} "
			"($SIGNING_KEY_PUB,$SIGNING_KEY_PRIV) do not contain"
			"valid creds" >&2
		exit 1
	fi
fi
if [[ -d "/enrollcertissuer" && ! -d "$GENCERT_CA_DIR" ]]; then
	echo "Copying cert-issuer creds to '$GENCERT_CA_DIR'"
	cp -r /enrollcertissuer $GENCERT_CA_DIR
	chown -R $HCP_ENROLLSVC_USER_DB $GENCERT_CA_DIR
	if [[ ! -f $GENCERT_CA_CERT || ! -f $GENCERT_CA_PRIV ]]; then
		echo "Error, GENCERT_CA_CERT" \
			"($GENCERT_CA_CERT,$GENCERT_CA_PRIV) do not contain"
			"valid creds" >&2
		exit 1
	fi
fi

# Create any symlinks in the rootfs that are expected
if [[ ! -h /etc/sudoers.d/hcp ]] &&
		! ln -s "$HCP_ENROLLSVC_STATE/sudoers" \
			/etc/sudoers.d/hcp > /dev/null 2>&1; then
	echo "Error, couldn't create symlink '/etc/sudoers.d/hcp'" >&2
	exit 1
fi
if [[ ! -h /install-safeboot/enroll.conf ]] &&
		! ln -s "$HCP_ENROLLSVC_STATE/safeboot-enroll.conf" \
			/install-safeboot/enroll.conf > /dev/null 2>&1; then
	echo "Error, couldn't create symlink '/install-safeboot/enroll.conf'" >&2
	exit 1
fi

# Done!
touch "$HCP_ENROLLSVC_LOCAL_INIT"
