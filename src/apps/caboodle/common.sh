source /hcp/common/hcp.sh

if [[ -n $HCP_CABOODLE_ALONE ]]; then

# We don't consume testcreds created by the host and mounted in, we spin up
# our own.
mkdir -p $HCP_EMGMT_CREDS_SIGNER
mkdir -p $HCP_EMGMT_CREDS_CERTISSUER
mkdir -p $HCP_ACLIENT_CREDS_VERIFIER
if [[ ! -f $HCP_EMGMT_CREDS_SIGNER/key.priv ]]; then
	echo "Generating: Enrollment signing key"
	openssl genrsa -out $HCP_EMGMT_CREDS_SIGNER/key.priv
	openssl rsa -pubout -in $HCP_EMGMT_CREDS_SIGNER/key.priv \
		-out $HCP_EMGMT_CREDS_SIGNER/key.pem
	chown db_user:db_user $HCP_EMGMT_CREDS_SIGNER/key.priv
fi
if [[ ! -f $HCP_ACLIENT_CREDS_VERIFIER/key.pem ]]; then
	echo "Generating: Enrollment verification key"
	cp $HCP_EMGMT_CREDS_SIGNER/key.pem $HCP_ACLIENT_CREDS_VERIFIER/
fi
if [[ ! -f $HCP_EMGMT_CREDS_CERTISSUER/CA.priv ]]; then
	echo "Generating: Enrollment certificate issuer (CA)"
	openssl genrsa -out $HCP_EMGMT_CREDS_CERTISSUER/CA.priv
	openssl req -new -key $HCP_EMGMT_CREDS_CERTISSUER/CA.priv \
		-subj /CN=localhost -x509 \
		-out $HCP_EMGMT_CREDS_CERTISSUER/CA.cert
	chown db_user:db_user $HCP_EMGMT_CREDS_CERTISSUER/CA.priv
fi

# Normal service containers get persistent storage mounted at these paths,
# which implicitly creates them. For caboodle, we need to mkdir them.
mkdir -p \
	$HCP_EMGMT_STATE \
	$HCP_EREPL_STATE \
	$HCP_AREPL_STATE \
	$HCP_AHCP_STATE \
	$HCP_ACLIENTTPM_STATE \
	$HCP_ACLIENTTPM_SOCKDIR

# Managing services within a caboodle container

mkdir -p /pids /logs

declare -A hcp_services=( \
	[enrollsvc_mgmt]=./enrollsvc_mgmt.env \
	[enrollsvc_repl]=./enrollsvc_repl.env \
	[attestsvc_repl]=./attestsvc_repl.env \
	[attestsvc_hcp]=./attestsvc_hcp.env \
	[attestclient_tpm]=./attestclient_tpm.env )

function hcp_service_is_specified {
	[[ -z $1 ]] &&
		echo "Error, HCP service not specified. Choose from;" &&
		echo "    ${!hcp_services[@]}" &&
		return 1
	return 0
}

function hcp_service_is_valid {
	hcp_service_is_specified $1 || return 1
	cmd=${hcp_services[$1]}
	[[ -z $cmd ]] &&
		echo "Error, unrecognized HCP service: $1. Choose from;" &&
		echo "    ${!hcp_services[@]}" &&
		return 1
	return 0
}

function hcp_service_is_started {
	hcp_service_is_valid $1 || return 1
	pidfile=/pids/$1
	[[ -f $pidfile ]] && return 0
	return 1
}

function hcp_service_start {
	pidfile=/pids/$1
	logfile=/logs/$1
	hcp_service_is_valid $1 || return 1
	if hcp_service_is_started $1; then
		echo "Error, HCP service $1 already has a PID file ($pidfile)"
		return 1
	fi
	HCP_INSTANCE="${hcp_services[$1]}" /hcp/common/launcher.sh > $logfile 2>&1 &
	echo $! > $pidfile
	echo "Started HCP service $1 (PID=$(cat $pidfile))"
}

function hcp_service_stop {
	pidfile=/pids/$1
	hcp_service_is_valid $1 || return 1
	if ! hcp_service_is_started $1; then
		echo "Error, HCP service $1 has no PID file ($pidfile)"
		return 1
	fi
	pid=$(cat $pidfile) &&
		kill -TERM $pid &&
		rm $pidfile ||
		(
			echo "Error, stopping HCP service $1 ($pidfile,$pid)"
			exit 1
		) || return 1
	echo "Stopped HCP service $1"
}

function hcp_service_alive {
	hcp_service_is_valid $1 || return 1
	hcp_service_is_started $1 || return 1
	pidfile=/pids/$1
	pid=$(cat $pidfile)
	if ! kill -0 $pid > /dev/null 2>&1; then
		return 1
	fi
	return 0
}

function hcp_services_start {
	echo "Starting all HCP services"
	for key in "${!hcp_services[@]}"; do
		if hcp_service_is_started $key; then
			echo "Skipping $key, already started"
		else
			hcp_service_start $key || return 1
		fi
	done
}

function hcp_services_stop {
	echo "Stopping all HCP services"
	for key in "${!hcp_services[@]}"; do
		if ! hcp_service_is_started $key; then
			echo "Skipping $key, not started"
		else
			hcp_service_stop $key || return 1
		fi
	done
}

function hcp_services_all_started {
	for key in "${!hcp_services[@]}"; do
		if ! hcp_service_is_started $key; then
			return 1
		fi
	done
	return 0
}

function hcp_services_any_started {
	for key in "${!hcp_services[@]}"; do
		if hcp_service_is_started $key; then
			return 0
		fi
	done
	return 1
}

function hcp_services_status {
	echo "HCP services status;"
	for key in "${!hcp_services[@]}"; do
		echo -n "$key: "
		if hcp_service_is_started $key; then
			if hcp_service_alive $key; then
				echo "started"
			else
				echo "FAILED"
			fi
		else
			echo "no started"
		fi
	done
}

fi

[[ -n $HCP_CABOODLE_SHELL ]] &&
(
echo "==============================================="

[[ -n $HCP_CABOODLE_ALONE ]] &&
(
echo "Interactive 'caboodle' session, running in alone/all-in-one mode."
echo ""
echo "To start/stop the HCP services within this container;"
echo "    hcp_services_start"
echo "    hcp_services_stop"
echo "    hcp_services_status"
echo "Or selectively, using the singular form rather than plural;"
echo "    hcp_service_<start|stop|status> <instance>"
echo "for <instance> in;"
for i in ${!hcp_services[@]}; do
echo "      - $i"
done
) ||
(
echo "Interactive 'caboodle' session, running networked for working with"
echo "service containers."
)
echo ""
echo "To run the attestation test;"
echo "    cd /hcp/usecase && ./caboodle_test.sh"
echo ""
echo "To run the soak-test (which creates its own software TPMs);"
echo "    /hcp/caboodle/soak.sh"
echo "using these (overridable) settings;"
echo "    HCP_SOAK_PREFIX (default: $HCP_SOAK_PREFIX)"
echo "    HCP_SOAK_NUM_SWTPMS (default: $HCP_SOAK_NUM_SWTPMS)"
echo "    HCP_SOAK_NUM_WORKERS (default: $HCP_SOAK_NUM_WORKERS)"
echo "    HCP_SOAK_NUM_LOOPS (default: $HCP_SOAK_NUM_LOOPS)"
echo "    HCP_SOAK_PC_ATTEST (default: $HCP_SOAK_PC_ATTEST)"
echo "    HCP_SOAK_NO_CREATE (default: $HCP_SOAK_NO_CREATE)"
echo ""
echo "To view or export the HCP environment variables;"
echo "    show_hcp_env"
echo "    export_hcp_env"
echo "==============================================="
)
