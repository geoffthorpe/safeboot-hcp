source /hcp/common/hcp.sh

# We pull the 'attestsvc' config once and then interrogate it locally.
export HCP_ATTESTSVC_JSON=$(hcp_config_extract ".attestsvc")
export HCP_ATTESTSVC_STATE=$(echo "$HCP_ATTESTSVC_JSON" | jq -r ".state")
export HCP_ATTESTSVC_GLOBAL_INIT=$(echo "$HCP_ATTESTSVC_JSON" | jq -r ".setup[0].touchfile")
export HCP_ATTESTSVC_LOCAL_INIT=$(echo "$HCP_ATTESTSVC_JSON" | jq -r ".setup[1].touchfile")
export HCP_ATTESTSVC_USER_DB=$(echo "$HCP_ATTESTSVC_JSON" | jq -r ".dbuser // empty")
if [[ -z $HCP_ATTESTSVC_USER_DB ]]; then
	export HCP_ATTESTSVC_USER_DB=auser
fi
export HCP_ATTESTSVC_USER_FLASK=$(echo "$HCP_ATTESTSVC_JSON" | jq -r ".webuser // empty")
if [[ -z $HCP_ATTESTSVC_USER_FLASK ]]; then
	export HCP_ATTESTSVC_USER_FLASK=ahcpflask
fi
export HCP_ATTESTSVC_REMOTE_REPO=$(echo "$HCP_ATTESTSVC_JSON" | jq -r ".enrollsvc")

export HCP_ATTESTSVC_DB_DIR="$HCP_ATTESTSVC_STATE/db"

if [[ $WHOAMI == "root" ]]; then
	hcp_config_user_init $HCP_ATTESTSVC_USER_DB
	hcp_config_user_init $HCP_ATTESTSVC_USER_FLASK
fi

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
