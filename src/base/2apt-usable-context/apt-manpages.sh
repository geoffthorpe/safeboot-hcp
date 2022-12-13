#!/bin/bash

set -e

if [[ -n $HCP_APT_MANPAGES ]]; then
	if egrep -rn "^path-exclude./usr/share/man" \
			/etc/dpkg/dpkg.cfg* > /dev/null 2>&1; then
		echo "Error, HCP_BASE ($HCP_BASE) disables 'man' pages" >&2
		exit 1
	fi
	apt-get install -y man manpages
else
	echo "Not enabling 'man' pages"
fi
