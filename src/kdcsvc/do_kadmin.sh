#!/bin/bash

# When a web handler (in mgmt_api.py, running as "www-data") runs 'sudo
# do_kadmin', we inhibit any transfer of environment through the sudo barrier
# as we want to protect against a compromised web app. So run_kdc.sh stores the
# environment at startup time, so that do_kadmin has a known-good source.
#
# So that's the only reason this bash wrapper exists, otherwise the sudo call
# would go directly to do_kadmin.py. I.e. python isn't very good at sourcing
# environment files...

set -e

source /root/exported.hcp.env

# Usage:
# do_kadmin.py <cmd> <principals_list> <options>
exec /hcp/kdcsvc/do_kadmin.py "$1" "$2" "$3"
