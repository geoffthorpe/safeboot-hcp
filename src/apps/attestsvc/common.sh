. /hcp/common/hcp.sh

function expect_root {
	if [[ `whoami` != "root" ]]; then
		echo "Error, running as \"`whoami`\" rather than \"root\"" >&2
		exit 1
	fi
}

# The root-written environment is stored here
export ATTESTSVC_ENV=/etc/environment.attestsvc

if [[ `whoami` != "root" ]]; then

	# We're not root, so we source the env-vars that root put there.
	if [[ -z "$HCP_ENVIRONMENT_SET" ]]; then
		echo "Running in reduced non-root environment (sudo probably)."
		source $ATTESTSVC_ENV
	fi

else # start of if(whoami==root)

if [[ ! -d $HCP_ATTESTSVC_STATE ]]; then
	echo "Error, HCP_ATTESTSVC_STATE ($HCP_ATTESTSVC_STATE) doesn't exist" >&2
	exit 1
fi
if [[ -z $HCP_ATTESTSVC_USER_HCP ]]; then
	echo "Error, HCP_ATTESTSVC_USER_HCP must be set" >&2
	exit 1
fi

# All the HCP_USER-owned stuff goes into this sub-directory
export HCP_USER_DIR=$HCP_ATTESTSVC_STATE/hcp

role_account_uid_file \
	$HCP_ATTESTSVC_USER_HCP \
	$HCP_ATTESTSVC_STATE/uid_hcp_user \
	"HCP User,,,,"

# Generate env file if it doesn't exist yet
if [[ ! -f $ATTESTSVC_ENV ]]; then
	echo " - generating '$ATTESTSVC_ENV'"
	touch $ATTESTSVC_ENV
	chmod 644 $ATTESTSVC_ENV
	echo "# HCP enrollsvc settings" > $ATTESTSVC_ENV
	export_hcp_env >> $ATTESTSVC_ENV
	echo "export HCP_ENVIRONMENT_SET=1" >> $ATTESTSVC_ENV

fi

function drop_privs_hcp {
	exec su -c "$*" - $HCP_ATTESTSVC_USER_HCP
}

if [[ ! -f $HCP_ATTESTSVC_STATE/initialized ]]; then

	echo "Initializing attestsvc state"

	echo " - generating HCP_USER-owned data in '$HCP_USER_DIR'"
	mkdir $HCP_USER_DIR
	chown $HCP_ATTESTSVC_USER_HCP $HCP_USER_DIR

	echo "   - initializing enrollment data clones"
	(drop_privs_hcp /hcp/attestsvc/init_clones.sh)
	touch $HCP_ATTESTSVC_STATE/initialized
	echo "State now initialized"
fi

fi # end of if(whoami==root)

function expect_hcp_user {
	if [[ `whoami` != "$HCP_ATTESTSVC_USER_HCP" ]]; then
		echo "Error, running as \"`whoami`\" rather than \"$HCP_ATTESTSVC_USER_HCP\"" >&2
		exit 1
	fi
}
