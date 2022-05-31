#!/bin/bash

$DCOMPOSE up -d emgmt erepl arepl ahcp aclient_tpm
$DCOMPOSE up --exit-code-from orchestrator --abort-on-container-exit orchestrator || exit 1

$DCOMPOSE up --exit-code-from aclient --abort-on-container-exit aclient || exit 1
