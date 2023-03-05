source /hcp/common/hcp.sh

# We pull the 'sshsvc' config once and then interrogate it locally.
export HCP_SSHSVC_JSON=$(hcp_config_extract ".sshsvc")
export HCP_SSHSVC_STATE=$(echo "$HCP_SSHSVC_JSON" | jq -r ".state")
export HCP_SSHSVC_GLOBAL_INIT=$(echo "$HCP_SSHSVC_JSON" | jq -r ".setup[0].touchfile")
export HCP_SSHSVC_LOCAL_INIT=$(echo "$HCP_SSHSVC_JSON" | jq -r ".setup[1].touchfile")

export HCP_SSHSVC_ETC="$HCP_SSHSVC_STATE/etc"
