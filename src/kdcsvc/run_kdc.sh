#!/bin/bash

# As a general rule, we do attestation before all the initialization flow.
# However, our attestation callback relies on the existence of
# $HCP_KDC_STATE/etc because it deposits our credential there, so take care of
# that pre-attestation.
if [[ -z $HCP_KDC_STATE ]]; then
	echo "Error, 'HCP_KDC_STATE' not defined" >&2
	exit 1
fi
if [[ ! -d $HCP_KDC_STATE ]]; then
	echo "Error, '$HCP_KDC_STATE' (HCP_KDC_STATE) doesn't exist" >&2
	exit 1
fi

# Run the attestation and get our assets
# Note, run_client is not a service, it's a utility, so it doesn't retry
# forever waiting for things to be ready to succeed. We, on the other hand,
# _are_ a service, so we need to be more forgiving.
attestlog=$(mktemp)
if ! /hcp/tools/run_client.sh 2> $attestlog; then
	echo "Warning: the attestation client lost patience, error output follows;" >&2
	cat $attestlog >&2
	rm $attestlog
	echo "Warning: suppressing error output from future attestation attempts" >&2
	attestation_done=
	until [[ -n $attestation_done ]]; do
		echo "Warning: waiting 10 seconds before retring attestation" >&2
		sleep 10
		echo "Retrying attestation" >&2
		/hcp/tools/run_client.sh 2> /dev/null && attestation_done=yes
	done
fi

if [[ ! -x $(which kdc) ]]; then
	echo "Error, no KDC binary found"
	exit 1
fi
if [[ ! -x $(which kpasswdd) ]]; then
	echo "Error, no KPASSWDD binary found"
	exit 1
fi
if [[ ! -x $(which kadmind) ]]; then
	echo "Error, no KADMIND binary found"
	exit 1
fi

MYETC=$HCP_KDC_STATE/etc
MYVAR=$HCP_KDC_STATE/var

# Handle first-time init of persistent state
if [[ ! -f $HCP_KDC_STATE/initialized ]]; then

	echo "Initializing KDC state"
	if [[ -z $HCP_KDC_REALM ]]; then
		echo "Error, HCP_KDC_REALM isn't set" >&2
		exit 1
	fi
	mkdir $MYETC
	mkdir $MYVAR

	# Produce script.kadmin
	echo "Creating $MYETC/script.kadmin"
	cat > $MYETC/script.kadmin << EOF
init --realm-max-ticket-life=unlimited --realm-max-renewable-life=unlimited $HCP_KDC_REALM
ext_keytab --keytab=$MYVAR/kadmin.keytab kadmin/admin kadmin/changepw
add_ns --key-rotation-epoch=-10d --key-rotation-period=5d --max-ticket-life=1d --max-renewable-life=5d --attributes= _/$HCP_KDC_NAMESPACE@$HCP_KDC_REALM
add_ns --key-rotation-epoch=-10d --key-rotation-period=5d --max-ticket-life=1d --max-renewable-life=5d --attributes=ok-as-delegate host/$HCP_KDC_NAMESPACE@$HCP_KDC_REALM
add --use-defaults -p somepassword somebody/admin@$HCP_KDC_REALM
EOF

	# Produce kdc.conf
	echo "Creating $MYETC/kdc.conf"
	cat > $MYETC/kdc.conf << EOF
# Autogenerated from run_kdc.sh
[logging]
	kdc = STDERR
	kpasswdd = STDERR
	kadmind = STDERR
[kdc]
	database = {
		dbname = $MYVAR/heimdal
		acl_file = $MYETC/kadmind.acl
		log_file = $MYVAR/kdc.log
	}
	enable-pkinit = yes
	synthetic_clients = true
	pkinit_identity = FILE:/etc/ssl/hostcerts/hostcert-pkinit-kdc-key.pem
	pkinit_anchors = FILE:/usr/share/ca-certificates/HCP/certissuer.pem
	#pkinit_pool = PKCS12:/path/to/useful-intermediate-certs.pfx
	#pkinit_pool = FILE:/path/to/other-useful-intermediate-certs.pem
	pkinit_allow_proxy_certificate = no
	pkinit_win2k_require_binding = yes
	pkinit_principal_in_certificate = yes
EOF

	# Produce kadmind.acl
	echo "Creating $MYETC/kadmind.acl"
	cat > $MYETC/kadmind.acl << EOF
# Autogenerated from run_kdc.sh
somebody/admin  all
EOF

	echo "Initializing KDC via 'kadmin -l'"
	kadmin --config-file=$MYETC/kdc.conf -l < $MYETC/script.kadmin
	touch $HCP_KDC_STATE/initialized
fi

# Start the services. Note, we background all tasks except kdc, which we exec
# to as a last step. We're relying on there being an "--init"-style PID1 to
# reparent orphaned processes and forward signals.
echo "Starting the KDC suite of services"
echo "- kpasswdd --config-file=$MYETC/kdc.conf"
kpasswdd --config-file=$MYETC/kdc.conf &
echo "- kadmind --config-file=$MYETC/kdc.conf --keytab=$MYVAR/kadmin.keytab --realm=$HCP_KDC_REALM"
kadmind --config-file=$MYETC/kdc.conf --keytab=$MYVAR/kadmin.keytab --realm=$HCP_KDC_REALM &
echo "- kdc --config-file=$MYETC/kdc.conf"
exec kdc --config-file=$MYETC/kdc.conf