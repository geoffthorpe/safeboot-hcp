#!/bin/bash

# See test_sequential.sh for comments on this;
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

# Wrapper for 'workstation1' calls that need KRB5_CONFIG set. TODO, this
# should eventually disappear.
w1() { KRB5_CONFIG=/etc/hcp/workstation1/krb5.conf "$@"; }

title "Starting services"
do_core_start_lazy \
	emgmt_pol emgmt erepl arepl ahcp aclient_tpm \
	kdc_primary_tpm kdc_secondary_tpm \
	kdc_primary_pol kdc_secondary_pol \
	kdc_primary kdc_secondary \
	sherver sherver_tpm \
	workstation1_tpm
w1 do_core_start_lazy workstation1

title "Waiting for emgmt to be alive"
do_exec emgmt /hcp/common/webapi.sh healthcheck $RARGS

title "Enrolling TPMs for non-krb5-dependent entities"
do_core_fg orchestrator -c -e aclient kdc_primary kdc_secondary

title "Running a test attestation"
do_core_fg aclient $RARGS

title "Waiting for KDCs to be alive"
do_exec kdc_primary /hcp/common/webapi.sh healthcheck $RARGS
do_exec kdc_secondary /hcp/common/webapi.sh healthcheck $RARGS

title "Enrolling remaining TPMs"
do_core_fg orchestrator -c -e

title "Waiting for 'sherver' and 'workstation1' to be alive"
do_exec sherver /hcp/sshsvc/healthcheck.sh $RARGS
w1 do_exec workstation1 /hcp/caboodle/networked_healthcheck.sh $RARGS

title "Extracting sherver's ssh hostkey"
do_exec sherver bash -c "ssh-keyscan sherver.hcphacking.xyz" > $tmpfile

title "Getting workstation1 to pre-trust sherver's ssh hostkey"
cmdstr="mkdir -p /root/.ssh && chmod 600 /root/.ssh"
cmdstr="$cmdstr && cat - > /root/.ssh/known_hosts"
cat $tmpfile | w1 do_exec_t workstation1 bash -c "$cmdstr"

title "Running 'echo hello' over 'ssh' over 'pkinit'"
cmdstr="kinit -C FILE:/home/luser/.hcp/pkinit/user-luser-key.pem luser"
cmdstr="$cmdstr ssh -l luser sherver.hcphacking.xyz"
cmdstr="$cmdstr echo hello"
w1 do_exec_t workstation1 bash -c -l "$cmdstr" > $tmpfile
hopinghello=$(cat $tmpfile | sed 's/\r$//')
if [[ $hopinghello == hello ]]; then
	echo "Success"
else
	echo "Failure"
fi
