#!/bin/bash

$DCOMPOSE up -d enrollsvc_mgmt enrollsvc_repl \
		attestsvc_repl attestsvc_hcp \
		swtpmsvc

$DCOMPOSE up --exit-code-from attestclient --abort-on-container-exit attestclient
