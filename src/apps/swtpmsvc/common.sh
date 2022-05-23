# This is an include-only file. So no shebang header and no execute perms.

. /hcp/common/hcp.sh

set -e

# Print the base configuration
echo "Running '$0'"
show_hcp_env

if [[ ! -d "/safeboot/sbin" ]]; then
	echo "Error, /safeboot/sbin is not present"
	exit 1
fi
export PATH=$PATH:/safeboot/sbin
echo "Adding /safeboot/sbin to PATH"

if [[ -d "/install/bin" ]]; then
	export PATH=$PATH:/install/bin
	echo "Adding /install/sbin to PATH"
fi

if [[ -d "/install/lib" ]]; then
	export LD_LIBRARY_PATH=/install/lib:$LD_LIBRARY_PATH
	echo "Adding /install/lib to LD_LIBRARY_PATH"
	if [[ -d /install/lib/python3/dist-packages ]]; then
		export PYTHONPATH=/install/lib/python3/dist-packages:$PYTHONPATH
		echo "Adding /install/lib/python3/dist-packages to PYTHONPATH"
	fi
fi

cd $HCP_SWTPMSVC_STATE
