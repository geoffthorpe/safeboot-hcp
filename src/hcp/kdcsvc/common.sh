source /hcp/common/hcp.sh

export HCP_ID=$(hcp_config_extract_or "id" "unknown_id")

# We pull the 'kdcsvc' config once and then interrogate it locally.
export HCP_KDCSVC_JSON=$(hcp_config_extract ".kdcsvc")
export HCP_KDCSVC_STATE=$(echo "$HCP_KDCSVC_JSON" | jq -r ".state")
export HCP_KDCSVC_GLOBAL_INIT=$(echo "$HCP_KDCSVC_JSON" | jq -r ".setup[0].touchfile")
export HCP_KDCSVC_LOCAL_INIT=$(echo "$HCP_KDCSVC_JSON" | jq -r ".setup[1].touchfile")
export HCP_KDCSVC_MODE=$(echo "$HCP_KDCSVC_JSON" | jq -r ".mode")
export HCP_KDCSVC_SECONDARIES=$(echo "$HCP_KDCSVC_JSON" | jq -r ".secondaries // []")
export HCP_KDCSVC_REALM=$(echo "$HCP_KDCSVC_JSON" | jq -r ".realm")
export HCP_KDCSVC_NAMESPACE=$(echo "$HCP_KDCSVC_JSON" | jq -r ".namespace")
export HCP_KDCSVC_POLICYURL=$(echo "$HCP_KDCSVC_JSON" | jq -r ".policy_url")

echo "Parsed 'kdcsvc': $HCP_HOSTNAME"
echo "       STATE: $HCP_KDCSVC_STATE"
echo " GLOBAL_INIT: $HCP_KDCSVC_GLOBAL_INIT"
echo "  LOCAL_INIT: $HCP_KDCSVC_LOCAL_INIT"
echo "        MODE: $HCP_KDCSVC_MODE"
echo " SECONDARIES: $HCP_KDCSVC_SECONDARIES"
echo "       REALM: $HCP_KDCSVC_REALM"
echo "   NAMESPACE: $HCP_KDCSVC_NAMESPACE"
echo "   POLICYURL: $HCP_KDCSVC_POLICYURL"

if [[ ! -d $HCP_KDCSVC_STATE ]]; then
	echo "Error, enrollsvc::state isn't a directory: $HCP_KDCSVC_STATE" >&2
	exit 1
fi

if [[ -z $HCP_KDCSVC_REALM ]]; then
	echo "Error, HCP_KDCSVC_REALM isn't set" >&2
	exit 1
fi

if [[ -z $HCP_KDCSVC_NAMESPACE ]]; then
	echo "Error, HCP_KDCSVC_NAMESPACE isn't set" >&2
	exit 1
fi
