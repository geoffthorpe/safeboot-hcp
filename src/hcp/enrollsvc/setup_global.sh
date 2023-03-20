#!/bin/bash

source /hcp/enrollsvc/common.sh

expect_root

if [[ ! -d $HCP_ENROLLSVC_STATE ]]; then
	echo "Error, enrollsvc::state isn't a directory: $HCP_ENROLLSVC_STATE" >&2
	exit 1
fi

if [[ -f $HCP_ENROLLSVC_GLOBAL_INIT ]]; then
	echo "Error, setup_global.sh being run but already initialized:" >&2
	exit 1
fi

echo "Initializing (persistent) enrollsvc state"

# Write the 'sudoers' file
echo " - generating '$HCP_ENROLLSVC_STATE/sudoers'"
cat > "$HCP_ENROLLSVC_STATE/sudoers" <<EOF
# sudo rules for enrollsvc-mgmt > /etc/sudoers.d/hcp
Cmnd_Alias HCP = /hcp/enrollsvc/mgmt_sudo.sh
Defaults !lecture
Defaults !authenticate
$HCP_ENROLLSVC_USER_FLASK ALL = ($HCP_ENROLLSVC_USER_DB) HCP
EOF

# Define the non-HCP_* vars that safeboot expects, and write the 'env' file
echo " - generating '$HCP_ENROLLSVC_STATE/env'"
echo "# HCP enrollsvc environment settings" > $HCP_ENROLLSVC_STATE/env
chmod 644 $HCP_ENROLLSVC_STATE/env
export SIGNING_KEY_DIR=/home/$HCP_ENROLLSVC_USER_DB/enrollsigner
export SIGNING_KEY_PUB=$SIGNING_KEY_DIR/key.pem
export SIGNING_KEY_PRIV=$SIGNING_KEY_DIR/key.priv
export GENCERT_CA_DIR=/home/$HCP_ENROLLSVC_USER_DB/enrollcertissuer
export GENCERT_CA_CERT=$GENCERT_CA_DIR/CA.cert
export GENCERT_CA_PRIV=$GENCERT_CA_DIR/CA.pem
cat >> $HCP_ENROLLSVC_STATE/env <<EOF
export SIGNING_KEY_DIR=$SIGNING_KEY_DIR
export SIGNING_KEY_PUB=$SIGNING_KEY_PUB
export SIGNING_KEY_PRIV=$SIGNING_KEY_PRIV
export GENCERT_CA_DIR=$GENCERT_CA_DIR
export GENCERT_CA_CERT=$GENCERT_CA_CERT
export GENCERT_CA_PRIV=$GENCERT_CA_PRIV
EOF
echo "export HCP_ENVIRONMENT_SET=1" >> $HCP_ENROLLSVC_STATE/env
chmod 644 $HCP_ENROLLSVC_STATE/env

# Write the safeboot-enroll.conf template (each 'add' operation clones and
# modifies this before invoking safeboot's 'attest-enroll').
echo " - generating '$HCP_ENROLLSVC_STATE/safeboot-enroll.conf'"
cat > $HCP_ENROLLSVC_STATE/safeboot-enroll.conf <<EOF
# Autogenerated by enrollsvc/run_mgmt.sh
export GENCERT_CA_PRIV=$GENCERT_CA_PRIV
export GENCERT_CA_CERT=$GENCERT_CA_CERT
export DIAGNOSTICS=$DIAGNOSTICS
POLICIES[cert-hxtool]=pcr11
POLICIES[rootfskey]=pcr11
POLICIES[krb5keytab]=pcr11
EOF

# Initialize trust-anchors for TPM EKcerts
echo " - generating '$HCP_ENROLLSVC_STATE/tpm_vendors'"
mkdir $HCP_ENROLLSVC_STATE/tpm_vendors
if [[ -d $HCP_ENROLLSVC_VENDORS ]]; then
	TRUST_OUT="$HCP_ENROLLSVC_STATE/tpm_vendors" \
	TRUST_IN="$HCP_ENROLLSVC_VENDORS" \
	/hcp/enrollsvc/vendors_install.sh
else
	echo "   - No vendors founds ($HCP_ENROLLSVC_VENDORS)"
fi

# Finally, the main thing: run init_repo as the 'emgmtdb' user. This sets up a
# new enrollment database.
echo " - generating DB_USER-owned data in '$HCP_DB_DIR'"
mkdir $HCP_DB_DIR
chown $HCP_ENROLLSVC_USER_DB $HCP_DB_DIR
echo "   - initializing repo"
(ENROLLSVC_IN_SETUP=1 drop_privs_db /hcp/enrollsvc/init_repo.sh)

# Mark it all as done (services may be polling on the existence of this file).
touch "$HCP_ENROLLSVC_GLOBAL_INIT"
echo "State now initialized"
