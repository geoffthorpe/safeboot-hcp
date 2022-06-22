#!/bin/bash

if [[ ! -f hostcert-pkinit-kdc.pem ]]; then
	echo "Error, 'hostcert-pkinit-kdc.pem' missing" >&2
	exit 1
fi
echo "Retrieved KDC certificate"
cp hostcert-pkinit-kdc.pem $HCP_KDC_STATE/etc/kdc-cert.pem
chmod 400 $HCP_KDC_STATE/etc/kdc-cert.pem
