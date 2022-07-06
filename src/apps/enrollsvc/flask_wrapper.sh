#!/bin/bash

cd /hcp/enrollsvc

source common.sh

expect_flask_user

# Environment variable controls (aping those in sbin/attest-server);
# HCP_ENROLLSVC_UWSGI
#    Specifies the UWSGI executable. If not set, the default is;
#            uwsgi_python3
# HCP_ENROLLSVC_UWSGI_FLAGS
#    Specifies the listening/interface behavior. If not set, the default is;
#            --http :$HCP_ENROLLSVC_UWSGI_PORT \
#            --stats :$((HCP_ENROLLSVC_UWSGI_PORT+1))
# HCP_ENROLLSVC_UWSGI_PORT
#    Port for UWSGI to listen on.
#    - If a port number is provided on the command-line, it takes precedence.
#    - Defaults to "5000"
#    - If HCP_ENROLLSVC_UWSGI is set, this variable and any port number specified on
#      the command-line are both ignored.
# HCP_ENROLLSVC_UWSGI_OPTIONS:
#    If not set, default options will be used instead;
#            --processes 2 --threads 2
#    Set to "none" if you want the cmd to use no options at all.
#
# BTW, to avoid noise in the logs, we also add;
#    --route "^/healthcheck donotlog:"

UWSGI=${HCP_ENROLLSVC_UWSGI:=uwsgi_python3}
PORT=${HCP_ENROLLSVC_UWSGI_PORT:=5000}
STATS=$((HCP_ENROLLSVC_UWSGI_PORT+1))
UWSGI_FLAGS=${HCP_ENROLLSVC_UWSGI_FLAGS:=--http :$HCP_ENROLLSVC_UWSGI_PORT --stats :$STATS}
UWSGI_OPTS=${HCP_ENROLLSVC_UWSGI_OPTIONS:=--processes 2 --threads 2}
[[ "$UWSGI_OPTS" == "none" ]] && UWSGI_OPTS=

TO_RUN="$UWSGI \
	--plugin http \
	--wsgi-file mgmt_api.py \
	--callable app \
	$UWSGI_FLAGS \
	$UWSGI_OPTS"

# uwsgi takes SIGTERM as an indication to ... reload! So we need to translate
# SIGTERM to SIGQUIT to have the desired effect.
echo "Setting SIGTERM->SIGQUIT trap handler"
trap 'echo "Converting SIGTERM->SIGQUIT"; kill -QUIT $UPID' TERM

echo "Running: $TO_RUN"
$TO_RUN --route-if "equal:\${PATH_INFO};/healthcheck donotlog:" &
UPID=$!
wait $UPID
