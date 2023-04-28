#!/bin/bash

source /hcp/kdcsvc/common.sh

if [[ -f $HCP_ENROLLSVC_GLOBAL_INIT ]]; then
	echo "Error, setup_global.sh being run but already initialized:" >&2
	exit 1
fi

echo "Initializing (persistent) kdcsvc state"

mkdir $HCP_KDCSVC_STATE/etc
mkdir $HCP_KDCSVC_STATE/var

# Produce kdc.conf
echo "Creating $HCP_KDCSVC_STATE/etc/kdc.conf"
cat > $HCP_KDCSVC_STATE/etc/kdc.conf << EOF
# Autogenerated from run_kdc.sh
[kdc]
	database = {
		dbname = $HCP_KDCSVC_STATE/var/heimdal
		realm = $HCP_KDCSVC_REALM
	}
	signal_socket = $HCP_KDCSVC_STATE/var/signalsock-iprop
	iprop-acl = $HCP_KDCSVC_STATE/etc/iprop-secondaries
	enable-pkinit = yes
	synthetic_clients = true
	pkinit_identity = FILE:/etc/hcp/$HCP_ID/pkinit/kdc-key.pem
	pkinit_anchors = FILE:/usr/share/ca-certificates/$HCP_ID/certissuer.pem
	#pkinit_pool = PKCS12:/path/to/useful-intermediate-certs.pfx
	#pkinit_pool = FILE:/path/to/other-useful-intermediate-certs.pem
	pkinit_allow_proxy_certificate = no
	pkinit_win2k_require_binding = yes
	pkinit_principal_in_certificate = yes
[hdb]
	db-dir = $HCP_KDCSVC_STATE/var
	enable_virtual_hostbased_princs = true
	virtual_hostbased_princ_mindots = 1
	virtual_hostbased_princ_maxdots = 5
EOF
cat /etc/hcp/$HCP_ID/krb5.conf >> $HCP_KDCSVC_STATE/etc/kdc.conf

# Produce sudoers
echo "Creating $HCP_KDCSVC_STATE/etc/sudoers.env"
cat > $HCP_KDCSVC_STATE/etc/sudoers.env << EOF
export HCP_CONFIG_FILE=$HCP_CONFIG_FILE
export HCP_CONFIG_SCOPE=$HCP_CONFIG_SCOPE
export KRB5_CONFIG=$KRB5_CONFIG
EOF
# Note, we need instance-specific content because our sudoers file gets linked
# into /etc/sudoers.d/ like any/all other cotenant services that use sudo. We
# take $HCP_ID as a unique identifier but sanitize it for use by replacing any
# non-alpha characters and converting to capital letters.
export HCP_NICEID=$(echo "$HCP_ID" | sed -e "s/[\._-]/x/g" | sed -e "s/[a-z]/\U&/g")
echo "Creating $HCP_KDCSVC_STATE/etc/sudoers"
cat > $HCP_KDCSVC_STATE/etc/sudoers << EOF
# sudo rules for kdcsvc-mgmt > /etc/sudoers.d/
Cmnd_Alias $HCP_NICEID = /hcp/kdcsvc/do_kadmin.py
Defaults!$HCP_NICEID !lecture
Defaults!$HCP_NICEID !authenticate
Defaults!$HCP_NICEID env_file=$HCP_KDCSVC_STATE/etc/sudoers.env
www-data ALL = (root) $HCP_NICEID
EOF

if [[ $HCP_KDCSVC_MODE == "primary" ]]; then
	# Produce slaves
	echo "Creating $HCP_KDCSVC_STATE/etc/iprop-secondaries"
	echo "# Generated by run_kdc.sh" > $HCP_KDCSVC_STATE/etc/iprop-secondaries
	# TODO: this is bash, which is to whitespace what lightning is to an
	# oil spill. For now, just rely on space-delimiters doing the right
	# thing. The solution is to rewrite this in python, or anything else.
	junk=$(echo "$HCP_KDCSVC_SECONDARIES" | jq -r '.[]')
	for i in $junk; do
		echo "iprop/$i@$HCP_KDCSVC_REALM" >> $HCP_KDCSVC_STATE/etc/iprop-secondaries
	done
	# Produce script.kadmin
	echo "Creating $HCP_KDCSVC_STATE/etc/script.kadmin"
	cat > $HCP_KDCSVC_STATE/etc/script.kadmin << EOF
init --realm-max-ticket-life=unlimited --realm-max-renewable-life=unlimited $HCP_KDCSVC_REALM
add_ns --key-rotation-epoch=-6000s --key-rotation-period=3000s --max-ticket-life=600s --max-renewable-life=3000s --attributes= _/$HCP_KDCSVC_NAMESPACE@$HCP_KDCSVC_REALM
add_ns --key-rotation-epoch=-6000s --key-rotation-period=3000s --max-ticket-life=600s --max-renewable-life=3000s --attributes=ok-as-delegate host/$HCP_KDCSVC_NAMESPACE@$HCP_KDCSVC_REALM
EOF

	echo "Initializing KDC via 'kadmin -l'"
	kadmin --config-file=$HCP_KDCSVC_STATE/etc/kdc.conf -l < $HCP_KDCSVC_STATE/etc/script.kadmin
fi

# Mark it all as done (services may be polling on the existence of this file).
touch "$HCP_KDCSVC_GLOBAL_INIT"
echo "Global state now initialized"
