#!/bin/bash

# This callback looks for a 'krb5.conf' file and installs it in /etc

if [[ ! -f krb5.conf ]]; then
	echo "No 'krb5.conf' found, skipping" >&2
	exit 0
fi

echo "Installing /etc/krb5.conf"

if [[ -f /etc/krb5.conf ]]; then
	mv /etc/krb5.conf /etc/krb5.conf-replaced-by-hcp
fi

if ! cp krb5.conf /etc; then
	echo "Error, couldn't install /etc/krb5.conf"
	exit 1
fi
