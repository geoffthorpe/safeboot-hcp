#!/bin/bash

source /hcp/common/hcp.sh

myinstance=$(hcp_config_extract_or ".id" "unknown_id")

myservername=$(hcp_config_extract ".webapi.servername")
myport=$(hcp_config_extract ".webapi.port")
myhttps=$(hcp_config_extract_or ".webapi.https" "")
myapp=$(hcp_config_extract ".webapi.app")
myharakiri=$(hcp_config_extract_or ".webapi.harakiri" "600")
myclienttimeout=$(hcp_config_extract_or ".webapi.clienttimeout" "600")
myenv=$(hcp_config_extract_or ".webapi.uwsgi_env" "{}")
myuid=$(hcp_config_extract ".webapi.uwsgi_uid")
mygid=$(hcp_config_extract ".webapi.uwsgi_gid")

if [[ -n $myhttps ]]; then
	myservercert=$(hcp_config_extract ".webapi.https.certificate")
	myCA=$(hcp_config_extract ".webapi.https.client_CA")
	myhealthclient=$(hcp_config_extract ".webapi.https.healthclient")
fi

# We use uwsgi as the flask application server for our http end-points. We use
# nginx as our TLS (https) front-end, optionally. Instance-specific paths for
# the nginx/uwsgi configs are defined here and populated later on.
#
# - etcnginx and lognginx are directories, cloned from /etc/nginx and
#   /var/log/nginx respectively, with all files in the former filtered to
#   replace any mention of /etc/nginx or /var/log/nginx to their new locations.
# - etcuwsgi is a 'uwsgi.ini' file, fully generated from this script.
# - etcjson is a directory created to store modified copies of the workload
#   (container) configuration and the policy configuration. Exotic docker
#   configurations can result in these input files being inaccessible to
#   non-root users. The policy config is copied to ensure it is readable when
#   privs are dropped, and the workload configuration is copied in order to
#   modify the env-settings that get consumed when producing the uwsgi.ini file.
# - myuwsgisock is a path in /tmp to use for the unix domain socket between
#   nginx and uwsgi.
myetc="/etc/hcp/$myinstance"
etcnginx="$myetc/nginx"
etcuwsgi="$myetc/uwsgi.ini"
etcjson="$myetc/json"
myvarlog="/var/log/$myinstance"
lognginx="$myvarlog/nginx"
myuwsgisock="/tmp/$myinstance.uwsgi.sock"

# Special handling. If we're invoked with the "healthcheck" argument, we're
# being asked to healthcheck the thing that we already started running (when
# previously invoked without the "healthcheck" argument). So we leverage the
# environment stuff above, but bypass the setting up and running of webservers
# that occur after this (admittedly oversized) "if" branch.
if [[ $1 == "healthcheck" ]]; then
	shift
	retries=0
	pause=1
	VERBOSE=0
	URL=$myservername:$myport/healthcheck
	CURLARG="-f -g --connect-timeout 2"
	if [[ -n $myhttps ]]; then
		URL=https://$URL
		CURLARG="$CURLARG --cacert $myCA"
		CURLARG="$CURLARG --cert $myhealthclient"
	else
		URL=http://$URL
	fi

	usage() {
		((${1:-1} == 0)) || exec 1>&2
		pager=cat
		if [[ -t 0 && -t 1 && -t 2 ]]; then
			if [[ -z ${PAGER:-} ]] && type less >/dev/null 2>&1; then
				pager=less
			elif [[ -z ${PAGER:-} ]] && type more >/dev/null 2>&1; then
				pager=more
			elif [[ -n ${PAGER:-} ]]; then
				pager=$PAGER
			fi
		fi
		$pager <<EOF
Usage: $PROG [OPTIONS]

  Queries the "/healthcheck" API of an HCP enrollsvc "mgmt" instance. This is
  used to determine if the service is alive, e.g. if a startup script needs to
  wait for the service to come up before initializing and, once it has, will
  treat any subsequent error as fatal.

  Options:

    -h               This message
    -v               Verbose
    -R <num>         Number of retries before failure
        (default: $retries)
    -P <seconds>     Time between retries
        (default: $pause)
    -U <url>         URL for healthcheck the API
        (default: $URL)
    -A <curl args>   Pre-URL arguments to 'curl'
        (default: $CURLARG)

EOF
		exit "${1:-1}"
	}

	while getopts +:R:P:U:A:hv opt; do
	case "$opt" in
	R)	retries="$OPTARG";;
	P)	pause="$OPTARG";;
	U)	URL="$OPTARG";;
	A)	CURLARG="$OPTARG";;
	h)	usage 0;;
	v)	((VERBOSE++)) || true;;
	*)	echo >&2 "Unknown option: $opt"; usage;;
	esac
	done
	shift $((OPTIND - 1))
	(($# == 0)) || (echo 2> "Unexpected options: $@" && exit 1) || usage

	tout=$(mktemp)
	terr=$(mktemp)
	onexit() {
		((VERBOSE > 0)) && echo >&2 "In trap handler, removing temp files"
		rm -f "$tout" "$terr"
	}
	trap onexit EXIT

	if ((VERBOSE > 0)); then
		cat >&2 <<EOF
Starting $PROG:
 - retries=$retries
 - pause=$pause
 - VERBOSE=$VERBOSE
 - CURLARG=$CURLARG
 - URL=$URL
 - Temp stdout=$tout
 - Temp stderr=$terr
EOF
	fi

	while :; do
		((VERBOSE > 0)) && echo >&2 "Running: curl $CURLARG $URL"
		res=0
		curl $CURLARG $URL >$tout 2>$terr || res=$?
		if [[ $res == 0 ]]; then
			((VERBOSE > 0)) && echo >&2 "Success"
			exit 0
		fi
		((VERBOSE > 0)) && echo >&2 "Failed with code: $res"
		((VERBOSE > 1)) && echo >&2 "Error output:" && cat >&2 "$terr"
		if [[ $retries == 0 ]]; then
			echo >&2 "Failure, giving up"
			exit $res
		fi
		((retries--))
		((VERBOSE > 0)) && echo >&2 "Pausing for $pause seconds"
		sleep $pause
	done
	exit 0
fi

# Setup nginx iff we're enabling https
if [[ -n $myhttps ]]; then
	# /etc/nginx is the template for our instance-specific install
	if [[ -d $etcnginx ]]; then
		if [[ -d "$etcnginx.old" ]]; then
			echo " - deleting really old nginx config" >&2
			rm -rf "$etcnginx.old"
		fi
		echo " - moving old nginx config" >&2
		mv "$etcnginx" "$etcnginx.old"
	fi
	echo " - producing nginx config" >&2
	cp -a /etc/nginx "$etcnginx"
	# Search the configuration files for occurences of "/etc/nginx" or
	# "/var/log/nginx" and repoint them to our own.
	find "$etcnginx" -type f -exec perl -pi.bak \
		-e "s,/etc/nginx,$etcnginx,g" {} \;
	find "$etcnginx" -type f -exec perl -pi.bak \
		-e "s,/var/log/nginx,$lognginx,g" {} \;
	# create our site file
	cat > "$etcnginx/sites-enabled/$myservername" << EOF
server {
	listen                 $myport ssl;
	server_name	       $myservername;
	ssl_certificate        $myservercert;
	ssl_certificate_key    $myservercert;
	ssl_client_certificate $myCA;
	ssl_verify_client      on;

	location / {
		# Pass the standard stuff along that the distro's default nginx
		# install likes to pass along.
		include        uwsgi_params;
		uwsgi_read_timeout ${myclienttimeout}s;
		uwsgi_send_timeout ${myclienttimeout}s;

		# This is where uwsgi will be expecting us
		uwsgi_pass     unix:$myuwsgisock;
		# Pass the extra stuff that _we_ want the flask app to get
		uwsgi_param    SSL_CLIENT_CERT           \$ssl_client_cert;
		uwsgi_param    SSL_CLIENT_S_DN           \$ssl_client_s_dn;
		uwsgi_param    SSL_CLIENT_S_DN_LEGACY    \$ssl_client_s_dn_legacy;
	}
}
EOF
	# Ensure there's an 'instance'-specific log directory. Note, we copy
	# the baseline to ensure we have the perms we need, not because we want
	# the content. (Normally, the access.log and error.log files will be
	# empty.)
	if [[ ! -d "$lognginx" ]]; then
		echo " - making new nginx log dir" >&2
		mkdir -p "$(dirname "$lognginx")"
		cp -a /var/log/nginx "$lognginx"
	fi
	echo " - starting nginx" >&2
	nginx -c "$etcnginx/nginx.conf"
fi

# Handle JSON configs. We produce a modified version of the original
# HCP_CONFIG_FILE, put it in $etcjson, and repoint HCP_CONFIG_FILE to it. At
# that time, we also copy the policy config to the same directory.
if [[ $HCP_CONFIG_FILE == $etcjson/* ]]; then
	hlog 2 "webapi: config already inside '$etcjson'"
else
	mkdir -p -m 755 $etcjson
	hcpconfig="$etcjson/hcp_config_file"
	appconfig=$(cat "$HCP_CONFIG_FILE" | jq -r ".webapi.config // empty")
	if [[ -n $appconfig ]]; then
		newappconfig="$etcjson/appconfig.json"
		cat "$appconfig" | jq --indent 4 > "$newappconfig.tmp"
		chmod 444 "$newappconfig.tmp"
		if [[ ! -f "$newappconfig" ]] || ! cmp -s "$newappconfig" \
						"$newappconfig.tmp"; then
			mv -f "$newappconfig.tmp" "$newappconfig"
		else
			rm -f "$newappconfig.tmp"
		fi
		# copy the global config file and modify the field
		# with the appconfig path to use our copy
		cat "$HCP_CONFIG_FILE" | jq --indent 4 \
				--arg newappconfig "$newappconfig" \
				'. * {"webapi":{"config":$newappconfig}}' \
			> "$hcpconfig.tmp"
	else
		# copy the global config file, unchanged
		cat "$HCP_CONFIG_FILE" | jq --indent 4 \
			> "$hcpconfig.tmp"
	fi
	chmod 444 "$hcpconfig.tmp"
	if [[ ! -f "$hcpconfig.tmp" ]] || ! cmp -s "$hcpconfig" \
					"$hcpconfig.tmp"; then
		mv -f "$hcpconfig.tmp" "$hcpconfig"
	else
		rm -f "$hcpconfig.tmp"
	fi
	export HCP_CONFIG_FILE=$hcpconfig
fi

# Produce the uwsgi config. This varies slightly depending on whether we have
# an nginx https front-end (in which case we listen for native comms on a
# domain socket) or not (in which case we listen for HTTP on a TCP port).
if [[ -f "$etcuwsgi" ]]; then
	if [[ -f "$etcuwsgi.old" ]]; then
		echo " - deleting really old uwsgi config" >&2
		rm "$etcuwsgi.old"
	fi
	echo " - moving old uwsgi config" >&2
	mv "$etcuwsgi" "$etcuwsgi.old"
fi
echo " - producing uwsgi config" >&2
cat - > "$etcuwsgi" <<EOF
[uwsgi]
master = true
processes = 2
threads = 2
uid = $myuid
gid = $mygid
wsgi-file = $myapp
callable = app
die-on-term = true
route-if = equal:\${PATH_INFO};/healthcheck donotlog:
harakiri = $myharakiri
EOF
myenvkeys=($(echo "$myenv" | jq -r "keys[] // empty"))
for keyname in ${myenvkeys[@]}; do
	val=$(echo "$myenv" | jq -r ".[\"$keyname\"] // empty")
	echo "env = $keyname=$val" >> "$etcuwsgi"
done
if [[ -n $myhttps ]]; then
	cat - >> "$etcuwsgi" <<EOF
socket = $myuwsgisock
socket-timeout = $myclienttimeout
chmod-socket = 660
vacuum = true
EOF
else
	cat - >> "$etcuwsgi" <<EOF
plugin = http
http = :$myport
http-timeout = $myclienttimeout
stats = :$((myport+1))
EOF
fi
echo " - starting uwsgi" >&2
exec uwsgi_python3 --ini "$etcuwsgi"
