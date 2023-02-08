source /hcp/common/hcp.sh

# We pull the 'attestsvc' config once and then interrogate it locally.
export HCP_ATTESTSVC_JSON=$(hcp_config_extract ".attestsvc")
export HCP_ATTESTSVC_STATE=$(echo "$HCP_ATTESTSVC_JSON" | jq -r ".state")
export HCP_ATTESTSVC_GLOBAL_INIT=$(echo "$HCP_ATTESTSVC_JSON" | jq -r ".setup[0].touchfile")
export HCP_ATTESTSVC_LOCAL_INIT=$(echo "$HCP_ATTESTSVC_JSON" | jq -r ".setup[1].touchfile")
export HCP_ATTESTSVC_USER_DB=$(echo "$HCP_ATTESTSVC_JSON" | jq -r ".dbuser.id")
export HCP_ATTESTSVC_USER_DB_HANDLE=$(echo "$HCP_ATTESTSVC_JSON" | jq -r ".dbuser.handle")
export HCP_ATTESTSVC_USER_FLASK=$(echo "$HCP_ATTESTSVC_JSON" | jq -r ".webuser.id")
export HCP_ATTESTSVC_USER_FLASK_HANDLE=$(echo "$HCP_ATTESTSVC_JSON" | jq -r ".webuser.handle")
export HCP_ATTESTSVC_REMOTE_REPO=$(echo "$HCP_ATTESTSVC_JSON" | jq -r ".enrollsvc")

export HCP_ATTESTSVC_DB_DIR="$HCP_ATTESTSVC_STATE/db"

function do_attestsvc_uid_setup {
	role_account_uid_file \
		$HCP_ATTESTSVC_USER_DB  \
		$HCP_ATTESTSVC_USER_DB_HANDLE  \
		"DB User,,,,"
	role_account_uid_file \
		$HCP_ATTESTSVC_USER_FLASK  \
		$HCP_ATTESTSVC_USER_FLASK_HANDLE  \
		"Flask User,,,,"
}

function expect_root {
	if [[ $WHOAMI != "root" ]]; then
		echo "Error, running as \"$WHOAMI\" rather than \"root\"" >&2
		exit 1
	fi
}

function expect_db_user {
	if [[ $WHOAMI != "$HCP_ATTESTSVC_USER_DB" ]]; then
		echo "Error, running as \"$WHOAMI\" rather than \"$HCP_ATTESTSVC_USER_DB\"" >&2
		exit 1
	fi
}

function expect_flask_user {
	if [[ $WHOAMI != "$HCP_ATTESTSVC_USER_FLASK" ]]; then
		echo "Error, running as \"$WHOAMI\" rather than \"$HCP_ATTESTSVC_USER_FLASK\"" >&2
		exit 1
	fi
}

function drop_privs_db {
	exec su -c "$*" - $HCP_ATTESTSVC_USER_DB
}
