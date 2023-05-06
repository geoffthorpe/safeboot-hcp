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

title "Starting services"
do_core_start_lazy \
	emgmt_pol emgmt erepl arepl ahcp aclient_tpm \
	kdc_primary_tpm kdc_secondary_tpm \
	kdc_primary_pol kdc_secondary_pol \
	kdc_primary kdc_secondary \
	sherver sherver_tpm \
	workstation1 workstation1_tpm

title "Waiting for emgmt to be alive"
do_exec emgmt /hcp/webapi.py --healthcheck $RARGS

title "Enrolling TPMs for non-krb5-dependent entities"
do_core_fg orchestrator -c -e aclient kdc_primary kdc_secondary

title "Running a test attestation"
do_core_fg aclient $RARGS

title "Waiting for KDCs to be alive (webapi responding)"
do_exec kdc_primary /hcp/webapi.py --healthcheck $RARGS
do_exec kdc_secondary /hcp/webapi.py --healthcheck $RARGS

title "Waiting for secondary KDC to sync the realm"
do_exec kdc_secondary /hcp/kdcsvc/realm_healthcheck.py $RARGS

title "Enrolling remaining TPMs"
do_core_fg orchestrator -c -e

title "Waiting for 'sherver' and 'workstation1' to be alive"
do_exec sherver /hcp/sshd.py --healthcheck $RARGS
do_exec workstation1 /hcp/monolith/networked_healthcheck.sh $RARGS

title "Running 'echo hello' over 'ssh' over 'pkinit'"
cmdstr="kinit -C FILE:/home/luser/.hcp/pkinit/user-luser-key.pem luser"
cmdstr="$cmdstr ssh -l luser -p 2222 $SHERVER_FQDN"
cmdstr="$cmdstr echo hello"
# The same comments apply as found in test_sequential.sh
export VERBOSE=0
do_exec workstation1 bash -c -l "$cmdstr" > $tmpfile

if [[ $(cat $tmpfile) != 'hello' ]]; then
	echo "FAILURE: output not 'hello'" >&2
	exit 1
fi

title "Bring up everything that isn't already up"
do_normal_start_lazy bigbrother target

title "Success"
