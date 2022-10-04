#!/bin/bash

# By cd'ing to /, we make sure we're not influenced by the directory we were
# launched from.
cd /

echo "Starting 'mgmt' web API"

if [[ ! -f $HCP_KDC_UWSGI_INI ]]; then
	echo "Error, HCP_KDC_UWSGI_INI ($HCP_KDC_UWSGI_INI) isn't available" >&2
fi
if [[ ! -f $HCP_KDC_JSON ]]; then
	echo "Error, HCP_KDC_JSON ($HCP_KDC_JSON) isn't available" >&2
fi

# Ugh. If we're running in an exotic docker configuration (eg. rootless), the JSON input might
# be in a mount that the www-data user can't read. Another hack to the rescue;
newjson=$(mktemp)
cp "$HCP_KDC_JSON" "$newjson"
chmod 644 "$newjson"
export HCP_KDC_JSON="$newjson"

exec uwsgi_python3 --ini $HCP_KDC_UWSGI_INI
