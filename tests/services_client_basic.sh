#!/bin/bash

$DCOMPOSE up -d emgmt erepl arepl ahcp aclient_tpm
$DCOMPOSE run orchestrator || exit 1
$DCOMPOSE run aclient || exit 1
