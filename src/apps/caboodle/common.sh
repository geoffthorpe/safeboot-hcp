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

# Normal service containers have mounts for persistent storage and
# inter-container comms, which implicitly creates those paths as they're
# mounted. For caboodle though, we need to create them directly.
mkdir -p $(show_hcp_env | egrep "_STATE=\/" | sed -e "s/^.*_STATE=//" | uniq)
mkdir -p $(show_hcp_env | egrep "_SOCKDIR=\/" | sed -e "s/^.*_SOCKDIR=//" | uniq)

# Managing services within a caboodle container

mkdir -p /pids /logs

# Declare service existence and corresponding .env file
declare -A hcp_entity=( \
	[emgmt]=./emgmt.env \
	[erepl]=./erepl.env \
	[arepl]=./arepl.env \
	[ahcp]=./ahcp.env \
	[orchestrator]=./orchestrator.env \
	[kdc]=./kdc.env \
	[kdc_tpm]=./kdc_tpm.env \
	[aclient]=./aclient.env \
	[aclient_tpm]=./aclient_tpm.env \
        )
# Declare what type of service it is (lifetime)
declare -A hcp_entity_type=( \
	[emgmt]=service \
	[erepl]=service \
	[arepl]=service \
	[ahcp]=service \
	[orchestrator]=setup \
	[kdc]=service \
	[kdc_tpm]=service \
	[aclient]=util \
	[aclient_tpm]=service \
	)
# Ordered list of entities
hcp_entities=$(echo "${!hcp_entity[@]}" | tr " " "\n" | sort)

################
# hcp_entity_* #
################

function hcp_entity_is_valid {
	if [[ -z $1 || -z ${hcp_entity[$1]} ]]; then
		echo "Error, HCP entity '$1' not known. Choose from;"
		echo "    ${!hcp_entity[@]}"
		return 1
	fi
	return 0
}

function hcp_entity_is_type {
	hcp_entity_is_valid $1 || return 1
	mytype=${hcp_entity_type[$1]}
	if [[ $mytype != $2 ]]; then
		if [[ -n $3 ]]; then
			echo "Error, HCP entity '$1' not a $2 (it's a $mytype)"
		fi
		return 1
	fi
	return 0
}

function hcp_entity_must_type {
	hcp_entity_is_type $1 $2 yep
}

#################
# hcp_service_* #
#################

function hcp_service_is_started {
	hcp_entity_must_type $1 service || return 1
	pidfile=/pids/$1
	[[ -f $pidfile ]] && return 0
	return 1
}

function hcp_service_start {
	pidfile=/pids/$1
	logfile=/logs/$1
	hcp_entity_must_type $1 service || return 1
	if hcp_service_is_started $1; then
		echo "Error, HCP service $1 already has a PID file ($pidfile)"
		return 1
	fi
	HCP_INSTANCE="${hcp_entity[$1]}" \
		/hcp/common/launcher.sh > $logfile 2>&1 &
	echo $! > $pidfile
	echo "Started HCP service $1 (PID=$(cat $pidfile))"
}

function hcp_service_stop {
	pidfile=/pids/$1
	hcp_entity_must_type $1 service || return 1
	if ! hcp_service_is_started $1; then
		echo "Error, HCP service $1 has no PID file ($pidfile)"
		return 1
	fi
	if ! pid=$(cat $pidfile) && kill -TERM $pid &&
				rm $pidfile; then
		echo "Error, failed stopping HCP service $1 ($pidfile,$pid)"
		return 1
	fi
	echo "Stopped HCP service $1"
}

function hcp_service_alive {
	hcp_service_is_started $1 || return 1
	pidfile=/pids/$1
	pid=$(cat $pidfile)
	if ! kill -0 $pid > /dev/null 2>&1; then
		return 1
	fi
	return 0
}

###############
# hcp_setup_* #
###############

function hcp_setup_has_run {
	hcp_entity_must_type $1 setup || return 1
	pidfile=/pids/$1
	[[ -f $pidfile ]] && return 0
	return 1
}

function hcp_setup_run {
	pidfile=/pids/$1
	hcp_entity_must_type $1 setup || return 1
	if hcp_setup_has_run $1; then
		echo "Error, HCP setup $1 has already run"
		return 1
	fi
	echo "Starting HCP setup $1"
	HCP_INSTANCE="${hcp_entity[$1]}" /hcp/common/launcher.sh
	touch $pidfile
	echo "Completed HCP setup $1"
}

###############
# hcp_util_* #
###############

function hcp_util_run {
	hcp_entity_must_type $1 util || return 1
	HCP_INSTANCE="${hcp_entity[$1]}" /hcp/common/launcher.sh
}

###########
# Plurals #
###########

function hcp_start_all {
	echo "Starting all HCP services"
	for key in $hcp_entities; do
	case ${hcp_entity_type[$key]} in
	service)
		if hcp_service_is_started $key; then
			echo "Skipping $key, already started"
		else
			hcp_service_start $key || return 1
		fi
		;;
	esac
	done
}

function hcp_stop_all {
	echo "Stopping all HCP services"
	for key in $hcp_entities; do
	case ${hcp_entity_type[$key]} in
	service)
		if ! hcp_service_is_started $key; then
			echo "Skipping $key, not started"
		else
			hcp_service_stop $key || return 1
		fi
		;;
	esac
	done
}

function hcp_setup_all {
	echo "Running all HCP setups"
	for key in $hcp_entities; do
	case ${hcp_entity_type[$key]} in
	setup)
		if hcp_setup_has_run $key; then
			echo "Skipping $key, already run"
		else
			hcp_setup_run $key || return 1
		fi
		;;
	esac
	done
}

function hcp_status {
	echo "HCP service and setup status;"
	for key in $hcp_entities; do
	case ${hcp_entity_type[$key]} in
	service)
		echo -n "Service $key: "
		if hcp_service_is_started $key; then
			if hcp_service_alive $key; then
				echo "started"
			else
				echo "FAILED"
			fi
		else
			echo "not started"
		fi
		;;
	setup)
		echo -n "Setup $key: "
		if hcp_setup_has_run $key; then
			echo "done"
		else
			echo "not done"
		fi
		;;
	esac
	done
}

fi   # if(HCP_CABOODLE_ALONE)

if [[ -n $HCP_CABOODLE_SHELL ]]; then
echo "==============================================="
	if [[ -n $HCP_CABOODLE_ALONE ]]; then
echo "Interactive 'caboodle' session, running in alone/all-in-one mode."
echo ""
echo "To start/stop the HCP services (and setups) within this container;"
echo "    hcp_start_all"
echo "    hcp_stop_all"
echo "    hcp_status"
echo "Or manage inidividual services;"
echo "    hcp_service_<start|stop|status> <instance>"
echo "        where <instance> is one of;"
		for i in $hcp_entities; do
			if hcp_entity_is_type $i service; then
echo "          - $i"
			fi
		done
echo "Or perform inidividual setups;"
echo "    hcp_setup_<run|has_run> <instance>"
echo "        where <instance> is one of;"
		for i in $hcp_entities; do
			if hcp_entity_is_type $i setup; then
echo "          - $i"
			fi
		done
echo "Or run inidividual tools;"
echo "    hcp_util_run <instance>"
echo "        where <instance> is one of;"
		for i in $hcp_entities; do
			if hcp_entity_is_type $i util; then
echo "          - $i"
			fi
		done
	else
echo "Interactive 'caboodle' session, running networked for working with"
echo "service containers."
echo ""
echo "TBD: ALL OF THE FOLLOWING IS OUT OF DATE - NEEDS TO RE REOWRKED!!"
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
	fi
echo ""
echo "To view the HCP environment variables;"
echo "    show_hcp_env"
echo "==============================================="
fi
