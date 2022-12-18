#!/bin/bash

source /hcp/common/hcp.sh

myservername=$(hcp_config_extract ".webapi.servername")
myport=$(hcp_config_extract ".webapi.port")
myhttps=$(hcp_config_extract_or ".webapi.https" "")
myapp=$(hcp_config_extract ".webapi.app")
myenv=$(hcp_config_extract_or ".webapi.uwsgi_env" "{}")
myuid=$(hcp_config_extract ".webapi.uwsgi_uid")
mygid=$(hcp_config_extract ".webapi.uwsgi_gid")

if [[ -n $myhttps ]]; then
	myservercert=$(hcp_config_extract ".webapi.https.certificate")
	myCA=$(hcp_config_extract ".webapi.https.client_CA")
	myhealthclient=$(hcp_config_extract ".webapi.https.healthclient")
fi

myunique="$myservername.$myport"

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
	myuwsgisock="/tmp/$myunique.uwsgi.sock"
	# Copy /etc/nginx to a 'myunique'-specific directory
	if [[ -d "/etc/hcp-$myunique-nginx" ]]; then
		if [[ -d "/etc/hcp.old-$myunique-nginx" ]]; then
			echo " - deleting really old nginx config" >&2
			rm -rf "/etc/hcp.old-$myunique-nginx"
		fi
		echo " - moving old nginx config" >&2
		mv "/etc/hcp-$myunique-nginx" "/etc/hcp.old-$myunique-nginx"
	fi
	echo " - producing nginx config" >&2
	cp -a /etc/nginx "/etc/hcp-$myunique-nginx"
	# search and replace our paths
	find "/etc/hcp-$myunique-nginx" -type f -exec perl -pi.bak \
		-e "s,/etc/nginx,/etc/hcp-$myunique-nginx,g" {} \;
	find "/etc/hcp-$myunique-nginx" -type f -exec perl -pi.bak \
		-e "s,/var/log/nginx,/var/log/hcp-$myunique-nginx,g" {} \;
	# create our site file
	cat > "/etc/hcp-$myunique-nginx/sites-enabled/$myservername" << EOF
server {
	listen                 $myport ssl;
	server_name	       $myservername;
	ssl_certificate        $myservercert;
	ssl_certificate_key    $myservercert;
	ssl_client_certificate $myCA;
	ssl_verify_client      on;

	location / {
		# Pass the standard stuff along that the distro nginx likes to pass
		include        uwsgi_params;
		# This is where uwsgi will be expecting us
		uwsgi_pass     unix:$myuwsgisock;
		# Pass the extra stuff that _we_ want the flask app to get
		uwsgi_param    SSL_CLIENT_CERT           \$ssl_client_cert;
		uwsgi_param    SSL_CLIENT_S_DN           \$ssl_client_s_dn;
		uwsgi_param    SSL_CLIENT_S_DN_LEGACY    \$ssl_client_s_dn_legacy;
	}
}
EOF
	# Ensure there's a 'myunique'-specific log directory. Note, we copy
	# the baseline to ensure we have the perms we need, not because we want
	# the content. (Normally, the access.log and error.log files will be
	# empty.)
	if [[ ! -d "/var/log/hcp-$myunique-nginx" ]]; then
		echo " - making new nginx log dir" >&2
		cp -a /var/log/nginx "/var/log/hcp-$myunique-nginx"
	fi
	echo " - starting nginx" >&2
	nginx -c "/etc/hcp-$myunique-nginx/nginx.conf"
fi

# Produce the uwsgi config. This varies slightly depending on whether we have
# an nginx https front-end (in which case we listen for native comms on a
# domain socket) or not (in which case we listen for HTTP on a TCP port).
if [[ -f "/etc/hcp-$myunique-uwsgi.ini" ]]; then
	if [[ -f "/etc/hcp.old-$myunique-uwsgi.ini" ]]; then
		echo " - deleting really old uwsgi config" >&2
		rm "/etc/hcp.old-$myunique-uwsgi.ini"
	fi
	echo " - moving old uwsgi config" >&2
	mv "/etc/hcp-$myunique-uwsgi.ini" "/etc/hcp.old-$myunique-uwsgi.ini"
fi
echo " - producing uwsgi config" >&2
cat - > "/etc/hcp-$myunique-uwsgi.ini" <<EOF
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
EOF
myenvkeys=($(echo "$myenv" | jq -r "keys[] // empty"))
for keyname in ${myenvkeys[@]}; do
	val=$(echo "$myenv" | jq -r ".[\"$keyname\"] // empty")
	echo "env = $keyname=$val" >> "/etc/hcp-$myunique-uwsgi.ini"
done
if [[ -n $myhttps ]]; then
	cat - >> "/etc/hcp-$myunique-uwsgi.ini" <<EOF
socket = $myuwsgisock
chmod-socket = 660
vacuum = true
EOF
else
	cat - >> "/etc/hcp-$myunique-uwsgi.ini" <<EOF
plugin = http
http = :$myport
stats = :$((myport+1))
EOF
fi
echo " - starting uwsgi" >&2
exec uwsgi_python3 --ini "/etc/hcp-$myunique-uwsgi.ini"
