#!/bin/bash

echo "SERVICES_TEST: starting all services"
$DCOMPOSE up -d pol emgmt erepl arepl ahcp aclient_tpm

echo "SERVICES_TEST: waiting for emgmt to come up"
$DCOMPOSE exec emgmt /hcp/tools/emgmt_healthcheck.sh -R 9999

echo "SERVICES_TEST: running orchestrator"
$DCOMPOSE run orchestrator /hcp/tools/run_orchestrator.sh aclient

echo "SERVICES_TEST: waiting for ahcp to come up"
$DCOMPOSE exec ahcp /hcp/tools/ahcp_healthcheck.sh -R 9999

echo "SERVICES_TEST: running attestation client"
$DCOMPOSE run aclient /hcp/tools/run_client.sh -R 9999

echo "SERVICES_TEST: stopping all services"
# The trap in wrapper.sh takes care of stopping things
