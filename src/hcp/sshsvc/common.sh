source /hcp/common/hcp.sh

# We pull the 'sshsvc' config once and then interrogate it locally.
export HCP_SSHSVC_JSON=$(hcp_config_extract ".sshsvc")
export HCP_SSHSVC_STATE=$(echo "$HCP_SSHSVC_JSON" | jq -r ".state")
export HCP_SSHSVC_GLOBAL_INIT=$(echo "$HCP_SSHSVC_JSON" | jq -r ".setup[0].touchfile")
export HCP_SSHSVC_LOCAL_INIT=$(echo "$HCP_SSHSVC_JSON" | jq -r ".setup[1].touchfile")

export HCP_SSHSVC_ETC="$HCP_SSHSVC_STATE/etc"

# These steps need to happen during setup_global and setup_local, so they're bundled
# into this function.
function ensure_user_accounts {
	# Create some expected accounts
	role_account_uid_file user1 $HCP_SSHSVC_STATE/uid-user1 "Test User 1,,,,"
	role_account_uid_file user2 $HCP_SSHSVC_STATE/uid-user2 "Test User 2,,,,"
	role_account_uid_file user3 $HCP_SSHSVC_STATE/uid-user3 "Test User 3,,,,"
	role_account_uid_file alicia $HCP_SSHSVC_STATE/uid-alicia "Alicia Not-Alice,,,,"
	role_account_uid_file luser $HCP_SSHSVC_STATE/luser "For remote logins,,,,"
}
