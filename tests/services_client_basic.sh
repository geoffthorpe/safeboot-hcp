#!/bin/bash

$DCOMPOSE up -d enrollsvc_mgmt enrollsvc_repl \
		attestsvc_repl attestsvc_hcp \
		attestclient_tpm
$DCOMPOSE up --exit-code-from orchestrator --abort-on-container-exit orchestrator || exit 1

$DCOMPOSE up --exit-code-from attestclient --abort-on-container-exit attestclient || exit 1
