#!/bin/bash

source /hcp/sshsvc/common.sh

if [[ ! -d $HCP_SSHSVC_STATE ]]; then
	echo "Error, sshsvc::state isn't a directory: $HCP_SSHSVC_STATE" >&2
	exit 1
fi

if [[ -f $HCP_SSHSVC_GLOBAL_INIT ]]; then
	echo "Error, setup_global.sh being run but already initialized:" >&2
	exit 1
fi

echo "Initializing (persistent) sshsvc state"

mkdir -p $HCP_SSHSVC_ETC

# Create the host keys
ssh_algos="rsa ecdsa ed25519"
for t in $ssh_algos; do
	ssh-keygen -N "" -t $t -f $HCP_SSHSVC_ETC/hostkey_$t
done

# Create the sshd config
if [[ ! -f "$HCP_SSHSVC_ETC/config" ]]; then
	cat > "$HCP_SSHSVC_ETC/config" <<EOF
# Auto-generated by run_sshsvc.sh
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
PidFile /var/run/sshd.$HCP_ID.pid
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
GSSAPIAuthentication yes
GSSAPICleanupCredentials yes
PasswordAuthentication no
EOF
fi
for t in $ssh_algos; do
	echo "HostKey $HCP_SSHSVC_ETC/hostkey_$t" >> "$HCP_SSHSVC_ETC/config"
done

# Make sure accounts are created
ensure_user_accounts

# Mark it all as done (services may be polling on the existence of this file).
touch "$HCP_SSHSVC_GLOBAL_INIT"
echo "State now initialized"