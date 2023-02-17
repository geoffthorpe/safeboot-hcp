#!/bin/bash

# Figure out how to include the subroutines
# - USECASE_INC is the file name to include, defaulting to "test_include.sh"
# - USECASE_DIR, if set, is the directory where we should find it. Otherwise
#   we try two common cases;
#   - ./usecase/<file>  (eg. from the top-level of a safeboot-hcp devel tree)
#   - /usecase/<file>   (eg. from inside a monolith container)
USECASE_INC=${USECASE_INC:-test_include.sh}
if [[ -n $USECASE_DIR ]]; then
	if [[ ! -f $USECASE_DIR/$USECASE_INC ]]; then
		echo "Error, no '$USECASE_INC' at USECASE_DIR=$USECASE_DIR" >&2
		exit 1
	fi
	source $USECASE_DIR/$USECASE_INC
else
	if [[ -f ./usecase/$USECASE_INC ]]; then
		source ./usecase/$USECASE_INC
	elif [[ -f /usecase/$USECASE_INC ]]; then
		source /usecase/$USECASE_INC
	else
		echo "Error, no '$USECASE_INC' found. Set USECASE_{DIR,INC}" >&2
		exit 1
	fi
fi

# 'tmpfile' is for capturing output from (and feeding input to) commands.
tmpfile=$(mktemp)
trap 'rm -f $tmpfile' EXIT

# The default target list for a HCP-bootstrapped service is:
#       start-fqdn start-attester setup-global setup-local start-services
# The latter, with its use of "start-attester", implies the existence of a TPM.
# The launcher backgrounds the attester sub-service, but will block until there
# has been at least one successful attestion;
# - all the service's subsequent setup steps and service start-up can assume
#   the attestation has happened, implying that the TPM has been enrolled and
#   assets have been retrieved and installed locally. This can simplify the
#   setup logic in terms of error handling, existence tests, retry loops, etc.
# - if the creation and enrollment of TPMs (and/or the replication of
#   enrollments to the attestation service instances) is happening in parallel
#   or temporarily deferred for a while, the "start-attester" step handles the
#   synchronization problem on behalf of the service, by not proceeding until
#   the entity has been "HCP bootstrapped" (a successful first attestation).
#
# For this test, we want things to be sequential and provide no
# lazy-initialization, i.e.  the "setup-global" step must be performed
# explicitly, it won't happen automatically when starting the service.
# So, global setup uses these explicit target lists:
#        (HCP core)       start-fqdn setup-global
#   (HCP-bootstrapped)    start-fqdn start-attester setup-global
# and service start-up uses this list:
#        (HCP core)       start-fqdn setup-local start-services
#   (HCP-bootstrapped)    start-fqdn start-attester setup-local start-services

title "initializing enrollsvc state"
do_core_setup emgmt

title "starting enrollsvc containers"
do_core_start emgmt emgmt_pol erepl

title "waiting for replication service to come up"
do_exec erepl /hcp/enrollsvc/repl_healthcheck.sh $RARGS

title "initializing attestsvc state"
do_core_setup arepl

title "starting attestsvc containers"
do_core_start arepl ahcp

title "waiting for emgmt service to come up"
do_exec emgmt /hcp/common/webapi.sh healthcheck $RARGS

title "create aclient TPM"
do_core_fg orchestrator -- -c aclient

title "starting aclient TPM"
do_core_start aclient_tpm

title "wait for aclient TPM to come up"
do_exec aclient_tpm /hcp/swtpmsvc/healthcheck.sh $RARGS

title "run attestation client, expecting failure (unenrolled)"
do_core_fg aclient -w

title "enroll aclient TPM"
do_core_fg orchestrator -- -e aclient

title "run attestation client, expecting eventual success (enrolled)"
do_core_fg aclient -- $RARGS

title "create and enroll KDC TPMs"
do_core_fg orchestrator -- -c -e kdc_primary kdc_secondary

title "starting KDC TPMs and policy engines"
do_core_start kdc_primary_tpm kdc_secondary_tpm kdc_primary_pol kdc_secondary_pol

title "wait for kdc_primary TPM to come up"
do_exec kdc_primary_tpm /hcp/swtpmsvc/healthcheck.sh $RARGS

title "initializing kdc_primary state"
do_normal_setup kdc_primary

title "starting kdc_primary"
do_normal_start kdc_primary

title "wait for kdc_primary to come up"
do_exec kdc_primary /hcp/common/webapi.sh healthcheck $RARGS

title "wait for kdc_secondary TPM to come up"
do_exec kdc_secondary_tpm /hcp/swtpmsvc/healthcheck.sh $RARGS

title "initializing kdc_secondary state"
do_normal_setup kdc_secondary

title "start kdc_secondary"
do_normal_start kdc_secondary

title "wait for kdc_secondary to come up"
do_exec kdc_secondary /hcp/common/webapi.sh healthcheck $RARGS

title "create and enroll 'sherver' TPM"
do_core_fg orchestrator -- -c -e sherver

title "start sherver TPM"
do_core_start sherver_tpm

title "wait for sherver TPM to come up"
do_exec sherver_tpm /hcp/swtpmsvc/healthcheck.sh $RARGS

title "initializing sherver state"
do_normal_setup sherver

title "start sherver"
do_normal_start sherver

title "wait for sherver to come up"
do_exec sherver /hcp/sshsvc/healthcheck.sh $RARGS

title "create and enroll 'workstation1' TPM"
do_core_fg orchestrator -- -c -e workstation1

title "start TPM for client machine (workstation1)"
do_core_start workstation1_tpm

title "wait for client TPM to come up"
do_exec workstation1_tpm /hcp/swtpmsvc/healthcheck.sh $RARGS

title "initializing client machine (workstation1)"
do_normal_setup workstation1

title "start client machine (workstation1)"
do_normal_start workstation1

title "waiting for the client machine to be up"
do_exec workstation1 /hcp/monolith/networked_healthcheck.sh $RARGS

title "obtaining the sshd server's randomly-generated public key"
do_exec sherver bash -c "ssh-keyscan -p 2222 $SHERVER_FQDN" > $tmpfile

title "inject sshd pubkey into client's 'known_hosts'"
cmdstr="mkdir -p /root/.ssh && chmod 600 /root/.ssh"
cmdstr="$cmdstr && cat - > /root/.ssh/known_hosts"
cat $tmpfile | do_exec workstation1 bash -c "$cmdstr"

title "Use HCP cred to get TGT, then GSSAPI to ssh from client to sherver"
cmdstr="kinit -C FILE:/home/luser/.hcp/pkinit/user-luser-key.pem luser"
cmdstr="$cmdstr ssh -l luser -p 2222 $SHERVER_FQDN echo -n hello"
# NB: we intentionally do it twice, in case the first time comes with a
# "Warning: Permanently added the [...] for IP address [...] to the list of
# known hosts" message. Also, VERBOSE causes stuff to leak into the output,
# which is difficult to balance against the need for "-l" (without which ssh
# auth fails - TODO to figure that out).
export VERBOSE=0
do_exec workstation1 bash -c -l "$cmdstr" > $tmpfile
do_exec workstation1 bash -c -l "$cmdstr" > $tmpfile

if [[ $(cat $tmpfile) != 'hello' ]]; then
    echo "FAILURE: output not 'hello': x${x}x" >&2
    exit 1
fi

title "success"
