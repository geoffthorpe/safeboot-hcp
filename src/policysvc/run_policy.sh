#!/bin/bash

# By cd'ing to /, we make sure we're not influenced by the directory we were
# launched from.
cd /

echo "Running 'policysvc' service"

if [[ ! -f $HCP_POLICYSVC_UWSGI_INI ]]; then
	echo "Error, HCP_POLICYSVC_UWSGI_INI ($HCP_POLICYSVC_UWSGI_INI) isn't available" >&2
fi
if [[ ! -f $HCP_POLICYSVC_JSON ]]; then
	echo "Error, HCP_POLICYSVC_JSON ($HCP_POLICYSVC_JSON) isn't available" >&2
fi

# Ugh. If we're running in an exotic docker configuration (eg. rootless), the JSON input might
# be in a mount that the www-data user can't read. Another hack to the rescue;
newjson=$(mktemp)
cp "$HCP_POLICYSVC_JSON" "$newjson"
chmod 644 "$newjson"
export HCP_POLICYSVC_JSON="$newjson"

echo "policysvc, running uwsgi with the python flask app"
exec uwsgi_python3 --ini $HCP_POLICYSVC_UWSGI_INI
