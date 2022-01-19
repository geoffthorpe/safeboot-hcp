#!/bin/bash

# To handle the case where the persistent data isn't set up, we run a subshell
# that does limited environment checks and waits for the volume to be ready.
# This follows what the mgmt container does, which launches a similar limited
# environment to _perform_ the initialization.
(
	export DB_IN_SETUP=1

	. /hcp/enrollsvc/common.sh

	expect_root

	if [[ ! -f $HCP_ENROLLSVC_STATE_PREFIX/initialized ]]; then
		echo "Warning: state not initialized, initializing now" >&2
		# This is the one-time init hook, so make sure the mounted dir
		# has appropriate ownership
		chown db_user:db_user $HCP_ENROLLSVC_STATE_PREFIX
		drop_privs_db /hcp/enrollsvc/init_repo.sh
		touch $HCP_ENROLLSVC_STATE_PREFIX/initialized
		echo "State now initialized" >&2
	fi
)

# At this point, we can load (and check) the environment fully.

. /hcp/enrollsvc/common.sh

expect_root

# Validate that version is an exact match (obviously we need the same major,
# but right now we expect+tolerate nothing other than the same minor too).
(state_version=`cat $HCP_ENROLLSVC_STATE_PREFIX/version` &&
	[[ $state_version == $HCP_VER ]]) ||
(echo "Error: expected version $HCP_VER, but got '$state_version' instead" &&
	exit 1) || exit 1

# Persistent credentials are mounted but ownership is for root, naturally. We
# need them accessible to db_user. Easiest is to copy the directory to the
# user's home dir (which isn't persistent, so we can do this on each startup).

if [[ -z "$HCP_RUN_ENROLL_SIGNER" || ! -d "$HCP_RUN_ENROLL_SIGNER" ]]; then
	echo "Error, HCP_RUN_ENROLL_SIGNER is not a valid directory" >&2
	exit 1
fi
if [[ -z "$HCP_RUN_ENROLL_GENCERT" || ! -d "$HCP_RUN_ENROLL_GENCERT" ]]; then
	echo "Error, HCP_RUN_ENROLL_GENCERT is not a valid directory" >&2
	exit 1
fi

cp -r $HCP_RUN_ENROLL_SIGNER /home/db_user/enrollsig
cp -r $HCP_RUN_ENROLL_GENCERT /home/db_user/enrollca

export HCP_RUN_ENROLL_SIGNER=/home/db_user/enrollsig
export HCP_RUN_ENROLL_GENCERT=/home/db_user/enrollca

chown -R db_user $HCP_RUN_ENROLL_SIGNER
chown -R db_user $HCP_RUN_ENROLL_GENCERT

export SIGNING_KEY_PUB=$HCP_RUN_ENROLL_SIGNER/key.pem
export SIGNING_KEY_PRIV=$HCP_RUN_ENROLL_SIGNER/key.priv
export GENCERT_CA_CERT=$HCP_RUN_ENROLL_GENCERT/CA.cert
export GENCERT_CA_PRIV=$HCP_RUN_ENROLL_GENCERT/CA.priv

# Run the mgmt-specific checks (and fill in /etc/environmnet) the way all the other
# environment stuff is done inside common.sh

if [[ ! -f "$SIGNING_KEY_PUB" || ! -f "$SIGNING_KEY_PRIV" ]]; then
	echo "Error, HCP_RUN_ENROLL_SIGNER does not contain valid creds" >&2
	exit 1
fi
if [[ ! -f "$GENCERT_CA_CERT" || ! -f "$GENCERT_CA_PRIV" ]]; then
	echo "Error, HCP_RUN_ENROLL_GENCERT does not contain valid creds" >&2
	exit 1
fi

if [[ -z "$HCP_RUN_ENROLL_REALM" ]]; then
	echo "Error, HCP_RUN_ENROLL_REALM must be set" >&2
fi

if [[ -z "$DIAGNOSTICS" ]]; then
	export DIAGNOSTICS="false"
fi

# Append mgmt-specific settings to /etc/environment
echo "# Values filled in by enrollsvc/run_mgmt.sh after credential-handling" >> /etc/environment
echo "export HCP_RUN_ENROLL_SIGNER=$HCP_RUN_ENROLL_SIGNER" >> /etc/environment
echo "export HCP_RUN_ENROLL_GENCERT=$HCP_RUN_ENROLL_GENCERT" >> /etc/environment
echo "export HCP_RUN_ENROLL_REALM=$HCP_RUN_ENROLL_REALM" >> /etc/environment
echo "export SIGNING_KEY_PUB=$SIGNING_KEY_PUB" >> /etc/environment
echo "export SIGNING_KEY_PRIV=$SIGNING_KEY_PRIV" >> /etc/environment
echo "export GENCERT_CA_CERT=$GENCERT_CA_CERT" >> /etc/environment
echo "export GENCERT_CA_PRIV=$GENCERT_CA_PRIV" >> /etc/environment

# Use the passed-in values to seed the enrollment config for safeboot
touch /safeboot/enroll.conf
chmod 644 /safeboot/enroll.conf
echo "# Autogenerated by enrollsvc/run_mgmt.sh" > /safeboot/enroll.conf
echo "export GENPROGS+=(gencert)" >> /safeboot/enroll.conf
echo "export GENCERT_CA_PRIV=$GENCERT_CA_PRIV" >> /safeboot/enroll.conf
echo "export GENCERT_CA_CERT=$GENCERT_CA_CERT" >> /safeboot/enroll.conf
echo "export GENCERT_REALM=$HCP_RUN_ENROLL_REALM" >> /safeboot/enroll.conf
echo "export GENCERT_KEY_BITS=2048" >> /safeboot/enroll.conf
echo "export GENCERT_INCLUDE_SAN_PKINIT=true" >> /safeboot/enroll.conf
echo "export GENCERT_INCLUDE_SAN_DNSNAME=true" >> /safeboot/enroll.conf
echo "export GENCERT_X509_TOOLING=OpenSSL" >> /safeboot/enroll.conf
echo "export DIAGNOSTICS=$DIAGNOSTICS" >> /safeboot/enroll.conf

# Print the additional configuration (beyond what common.sh prints)
echo "               SIGNING_KEY_PRIV=$SIGNING_KEY_PRIV" >&2
echo "                SIGNING_KEY_PUB=$SIGNING_KEY_PUB" >&2

echo "Running 'enrollsvc-mgmt' service"

drop_privs_flask /hcp/enrollsvc/flask_wrapper.sh
