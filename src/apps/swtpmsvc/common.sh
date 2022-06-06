# This is an include-only file. So no shebang header and no execute perms.

. /hcp/common/hcp.sh

set -e

add_install
need_safeboot

cd $HCP_SWTPMSVC_STATE
