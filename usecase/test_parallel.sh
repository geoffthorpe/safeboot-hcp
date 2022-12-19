#!/bin/bash

if [[ -z $USECASE_DIR ]]; then
	if [[ -d ./usecase ]]; then
		USECASE_DIR=./usecase
	elif [[ -d /usecase ]]; then
		USECASE_DIR=/usecase
	elif [[ -d ../usecase ]]; then
		USECASE_DIR=.
	else
		echo "Error, USECASE_DIR undefined" >&2
		exit 1
	fi
fi

source $USECASE_DIR/test_include.sh

# 'tmpfile' is for capturing output from (and feeding input to) commands.
tmpfile=$(mktemp)
trap 'rm -f $tmpfile' EXIT

title "Starting services"
$(wrapper start) emgmt_pol emgmt erepl arepl ahcp aclient_tpm
$(wrapper start) kdc_primary_tpm kdc_secondary_tpm
$(wrapper start) kdc_primary_pol kdc_secondary_pol
$(wrapper start) kdc_primary kdc_secondary
$(wrapper start) sherver sherver_tpm
$(wrapper start) workstation1 workstation1_tpm

title "Waiting for emgmt to be alive"
$(wrapper exec) emgmt /hcp/common/webapi.sh healthcheck $RARGS

title "Enrolling TPMs for non-krb5-dependent entities"
$(wrapper run) orchestrator -c -e aclient kdc_primary kdc_secondary

title "Running a test attestation"
$(wrapper run) aclient

title "Waiting for KDCs to be alive"
$(wrapper exec) kdc_primary /hcp/common/webapi.sh healthcheck $RARGS
$(wrapper exec) kdc_secondary /hcp/common/webapi.sh healthcheck $RARGS

title "Enrolling remaining TPMs"
$(wrapper run) orchestrator -c -e

title "Waiting for 'sherver' and 'workstation1' to be alive"
$(wrapper exec) sherver /hcp/sshsvc/healthcheck.sh $RARGS
# TODO: see note in docker-compose.yml::workstation1 - setting this env-var
# should become unnecessary.
KRB5_CONFIG=/etc/hcp/workstation1/krb5.conf \
$(wrapper exec) workstation1 /hcp/caboodle/networked_healthcheck.sh $RARGS

title "Extracting sherver's ssh hostkey"
$(wrapper exec) sherver bash -c "ssh-keyscan sherver.hcphacking.xyz" > $tmpfile

title "Getting workstation1 to pre-trust sherver's ssh hostkey"
cmdstr="mkdir -p /root/.ssh && chmod 600 /root/.ssh"
cmdstr="$cmdstr && cat - > /root/.ssh/known_hosts"
cat $tmpfile | $(wrapper exec-t) workstation1 bash -c "$cmdstr"

title "Running 'echo hello' over 'ssh' over 'pkinit'"
cmdstr="kinit -C FILE:/home/luser/.hcp/pkinit/user-luser-key.pem luser"
cmdstr="$cmdstr ssh -l luser sherver.hcphacking.xyz"
cmdstr="$cmdstr echo hello"
# TODO: ditto
KRB5_CONFIG=/etc/hcp/workstation1/krb5.conf \
$(wrapper exec-t) workstation1 bash -c -l "$cmdstr" > $tmpfile
hopinghello=$(cat $tmpfile | sed 's/\r$//')
if [[ $hopinghello == hello ]]; then
	echo "Success"
else
	echo "Failure"
fi
