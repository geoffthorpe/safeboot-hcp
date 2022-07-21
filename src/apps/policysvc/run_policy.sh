#!/bin/bash

# By cd'ing to /, we make sure we're not influenced by the directory we were
# launched from.
cd /

echo "Running 'policysvc' service"

if [[ ! -f $HCP_POLICYSVC_UWSGI_INI ]]; then
	echo "Error, HCP_POLICYSVC_UWSGI_INI ($HCP_POLICYSVC_UWSGI_INI) isn't available" >&2
fi

echo "policysvc, running uwsgi with the python flask app"
exec uwsgi_python3 --ini $HCP_POLICYSVC_UWSGI_INI
