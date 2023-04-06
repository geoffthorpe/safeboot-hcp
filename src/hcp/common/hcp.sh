#!/bin/bash

# For interactive shells, don't "set -e", it can be (more than) mildly
# inconvenient to have the shell exit any time you run a command that returns a
# non-zero status code. It's good discipline for scripts though.
[[ -z $PS1 ]] && set -e

WHOAMI=$(whoami)

hcp_default_log_level=1
hcp_current_log_level=0
hcp_current_tracefile=""

if [[ -n $VERBOSE ]]; then
	hcp_current_log_level=$VERBOSE
fi

hlog() {
	if [[ $1 -gt $hcp_current_log_level ]]; then
		return
	fi
	if [[ -z $HCP_NOTRACEFILE ]]; then
		whoami=$(whoami)
		pid=$BASHPID
		procname=$(ps -p $pid -o comm=)
		dirdate=$(date --utc +%Y-%m-%d-%H)
		fdate=$(date --utc +%M-%S)
		fdir="/tmp/debug-$whoami-$dirdate"
		fname="$fdir/$fdate-$procname.$pid"
		if [[ $fname != $hcp_current_tracefile ]]; then
			mkdir -p $fdir
			if [[ -n $hcp_current_tracefile || $hcp_current_log_level -gt 1 ]]; then
				echo "[tracefile forking to $fname]" >&2
			fi
			exec 2>> $fname
			echo "[tracefile forked from $hcp_current_tracefile]" >&2
			hcp_current_tracefile=fname
		fi
	fi
	echo -E "$2" >&2
	sync
}

log() {
	hlog $hcp_default_log_level "$1"
}

bail() {
	hlog 0 "FAIL: $1"
	exit 1
}

# Our web-handling code (particularly for enrollsvc) relies heavily on
# processing that executes child processes synchronously. This includes using
# tpm tools, safeboot scripts, "genprogs", and so forth. Furthermore, the
# webhandlers are typically running as a low-priv userid to protect the fallout
# from a successful exploit of anything in that stack (uwsgi, nginx, flask, etc) and
# they defer "real work" via a curated sudo call to
# run those tasks as a different non-root user. Throughout this handling, we rely on
# two assumptions:
# 1 - if the operation is successful, then the response to the web request is
#     whatever got written to stdout (typically a JSON-encoding), and
# 2 - the concept of what "successful" means is conveyed via exit codes, and if
#     that results in failure then whatever is written to stdout is _not_ sent
#     to the client. (In this way output can be produced sequentially knowing
#     that if an error occurs later on the output doesn't need to be
#     "un-written".)
# We want to follow the http model, in that 2xx codes represent success, 4xx
# codes represent request problems, 5xx codes represent server issues, etc.
# This doesn't map well to the posix conventions for process exit codes. For
# one, we have more than one success code (we only need 200 and 201, but that's
# more than one). Also, exit codes are 8-bit, so we can't use the http status
# codes literally as process exit codes. We use the following conventions
# instead, and that's why we have the following functions and definitions.
#
#   http codes   ->   exit codes   ->   http codes
#       200               20               200   (most success cases)
#       201               21               201   (success creating a record)
#       400               40               400   (malformed input)
#       401               41               401   (authentication failure)
#       403               43               403   (authorization failure)
#       404               44               404   (resource not found)
#       500               50               500   (misc server failure)
#       xxx               49               500   (unexpected http code)
#                          0               200   (posix success, not http-aware)
#                         xx               500   (unexpected exit code)
#
declare -A ahttp2exit=(
	[200]=20, [201]=21,
	[400]=40, [401]=41, [403]=43, [404]=44,
	[500]=50)
declare -A aexit2http=(
	[20]=200, [21]=201,
	[40]=400, [41]=401, [43]=403, [44]=404,
	[50]=500, [49]=500, [0]=200)
aahttp2exit="${!ahttp2exit[@]}"
function http2exit {
	val=""
	for key in $aahttp2exit; do
		if [[ $1 == $key ]]; then
			val=${ahttp2exit[$key]}
			break
		fi
	done
	if [[ -n $val ]]; then
		echo $val
		return
	fi
	echo 49
}
aaexit2http="${!aexit2http[@]}"
function exit2http {
	val=""
	for key in $aaexit2http; do
		if [[ $1 == $key ]]; then
			val=${aexit2http[$key]}
			break
		fi
	done
	if [[ -n $val ]]; then
		echo $val
		return
	fi
	echo 500
}

# Until all the relevant code can migrate from bash to python, we need some
# equivalent functionality. This mimics the "hcp_config_*" functions in
# hcp_common.py.
function normalize_path {
	if [[ $1 =~ ^\. ]]; then
		mypath=$1
	else
		mypath=".$1"
	fi
	echo "$mypath"
}
workloadpath=/tmp/workloads
if [[ ! -n $HCP_CONFIG_FILE ]]; then
	if [[ -n $HOME && -d $HOME && -f "$HOME/hcp_config" ]]; then
		source "$HOME/hcp_config"
		hlog 2 "hcp_config: loaded from $HOME/hcp_config"
	elif [[ -f /etc/hcp-monolith-container.env ]]; then
		source /etc/hcp-monolith-container.env
		hlog 2 "hcp_config: loaded from /etc/hcp-monolith-container.env"
	else
		echo "Warning, no HCP_CONFIG_FILE set, use of APIs may 'exit'" >&2
	fi
elif [[ $HCP_CONFIG_FILE == ${workloadpath}/* ]]; then
	hlog 2 "hcp_config: already relocated ($curpath)"
else
	if [[ $WHOAMI != root ]]; then
		echo "Warning, HCP_CONFIG_FILE ($HCP_CONFIG_FILE) not relocated" >&2
	else
		fname=$(basename "$HCP_CONFIG_FILE")
		newpath="$workloadpath/$fname"
		hlog 2 "hcp_config: relocating"
		hlog 2 "- from: $HCP_CONFIG_FILE"
		hlog 2 "-   to: $newpath"
		mkdir -p -m 755 $workloadpath
		cat "$HCP_CONFIG_FILE" | jq '.' > "$newpath.tmp"
		chmod 444 "$newpath.tmp"
		mv "$newpath.tmp" "$newpath"
		export HCP_CONFIG_FILE=$newpath
	fi
fi
function hcp_config_scope_set {
	if [[ -z $HCP_CONFIG_FILE ]]; then
		bail "!HCP_CONFIG_FILE"
	fi
	mypath=$(normalize_path "$1")
	hlog 2 "hcp_config_scope_set: $mypath"
	# Deliberately fail (ie. don't proceed) if mypath doesn't exist.
	cat "$HCP_CONFIG_FILE" | jq -r "$mypath" > /dev/null 2>&1
	export HCP_CONFIG_SCOPE=$mypath
}
function hcp_config_scope_get {
	if [[ -z $HCP_CONFIG_FILE ]]; then
		bail "!HCP_CONFIG_FILE"
	fi
	# If HCP_CONFIG_SCOPE isn't set, it's possible we're the first context
	# started. In which case the world we're given is supposed to be our
	# starting context, in which case our initial region is ".".
	if [[ ! -n $HCP_CONFIG_SCOPE ]]; then
		hlog 2 "hcp_config_scope_get: default HCP_CONFIG_SCOPE='.'"
		hcp_config_scope_set "."
	fi
	hlog 2 "hcp_config_scope_get: returning $HCP_CONFIG_SCOPE"
	echo $HCP_CONFIG_SCOPE
}
# We want to trigger the lazy-initialization of hcp_config_scope_get() on first
# use of the API, but not before (we don't want to do it at all in those cases
# where the API is unused). If the first API call is hcp_config_scope_get()
# itself, problem self-solved, otherwise we just call it quietly at the start
# of other APIs to get the desired behavior.
function hcp_config_scope_shrink {
	if [[ -z $HCP_CONFIG_FILE ]]; then
		bail "!HCP_CONFIG_FILE"
	fi
	hcp_config_scope_get > /dev/null
	mypath=$(normalize_path "$1")
	hlog 2  "hcp_config_scope_shrink: $mypath"
	if [[ $HCP_CONFIG_SCOPE != "." ]]; then
		mypath="$HCP_CONFIG_SCOPE$mypath"
	fi
	hcp_config_scope_set "$mypath"
}
function hcp_config_extract {
	if [[ -z $HCP_CONFIG_FILE ]]; then
		bail "!HCP_CONFIG_FILE"
	fi
	hcp_config_scope_get > /dev/null
	mypath=$(normalize_path "$1")
	result=$(cat "$HCP_CONFIG_FILE" | jq -r "$HCP_CONFIG_SCOPE" | jq -r "$mypath")
	hlog 3 "hcp_config_extract: $HCP_CONFIG_FILE,$HCP_CONFIG_SCOPE,$mypath"
	echo "$result"
}
function hcp_config_extract_or {
	if [[ -z $HCP_CONFIG_FILE ]]; then
		bail "!HCP_CONFIG_FILE"
	fi
	hcp_config_scope_get > /dev/null
	# We need a string that will never occur and yet contains no odd
	# characters that will screw up 'jq'. Thankfully this is just a
	# temporary thing until bash->python is complete.
	s="astringthatneveroccursever"
	mypath=$(normalize_path "$1")
	result=$(cat "$HCP_CONFIG_FILE" | jq -r "$HCP_CONFIG_SCOPE" | jq -r "$mypath // \"$s\"")
	if [[ $result == $s ]]; then
		result=$2
	fi
	log "hcp_config_extract_or: $HCP_CONFIG_FILE,$HCP_CONFIG_SCOPE,$mypath,$2"
	echo "$result"
}

function hcp_config_user_init {
	USERNAME=$1
	if [[ ! -d /home/$USERNAME ]]; then
		bail "No directory at /home/$USERNAME"
	fi
	if [[ ! -f /home/$USERNAME/hcp_config ]]; then
		cat > /home/$USERNAME/hcp_config <<EOF
export HCP_CONFIG_FILE="$HCP_CONFIG_FILE"
export HCP_CONFIG_SCOPE="$HCP_CONFIG_SCOPE"
EOF
		chown $USERNAME /home/$USERNAME/hcp_config
	fi
}

function add_env_path {
	if [[ -n $1 ]]; then
		echo "$1:$2"
	else
		echo "$2"
	fi
}

function add_install_path {
	local D=$1
	if [[ ! -d $D ]]; then return; fi
	if [[ -d "$D/bin" ]]; then
		export PATH=$(add_env_path "$PATH" "$D/bin")
	fi
	if [[ -d "$D/sbin" ]]; then
		export PATH=$(add_env_path "$PATH" "$D/sbin")
	fi
	if [[ -d "$D/libexec" ]]; then
		export PATH=$(add_env_path "$PATH" "$D/libexec")
	fi
	if [[ -d "$D/lib" ]]; then
		export LD_LIBRARY_PATH=$(add_env_path \
			"$LD_LIBRARY_PATH" "$D/lib")
		if [[ -d "$D/lib/python/dist-packages" ]]; then
			export PYTHONPATH=$(add_env_path \
				"$PYTHONPATH" "$D/lib/python/dist-packages")
		fi
	fi

}

function source_safeboot_functions {
	if [[ ! -f /install-safeboot/functions.sh ]]; then
		echo "Error, Safeboot 'functions.sh' isn't installed"
		return 1
	fi
	source "/install-safeboot/functions.sh"
}

function show_hcp_env {
	printenv | egrep -e "^HCP_" | sort
}

function export_hcp_env {
	printenv | egrep -e "^HCP_" | sort | sed -e "s/^HCP_/export HCP_/" |
		sed -e "s/\"/\\\"/" | sed -e "s/=/=\"/" | sed -e "s/$/\"/"
}

# Utility for adding a PEM file to the set of trust roots for the system. This
# can be called multiple times to update (if changed) the same trust roots, eg.
# when used inside an attestation-completion callback. As such, $2 and $3
# specify a CA-store subdirectory and filename (respectively) to use for the
# PEM file being added. If the same $2 and $3 arguments are provided later on,
# it is assumed to be an update to the same trust roots.
# $1 = file containing the trust roots
# $2 = CA-store subdirectory (can be multiple layers deep)
# $3 = CA-store filename
function add_trust_root {
	if [[ ! -f $1 ]]; then
		echo "Error, no '$1' found" >&2
		return 1
	fi
	echo "Adding '$1' as a trust root"
	if [[ -f "/usr/share/ca-certificates/$2/$3" ]]; then
		if cmp "$1" "/usr/share/ca-certificates/$2/$3"; then
			echo "  - already exists and hasn't changed, skipping"
			return 0
		fi
		echo "  - exists but has changd, overriding"
		cp "$1" "/usr/share/ca-certificates/$2/$3"
		update-ca-certificates
	else
		echo "  - no prior trust root, installing"
		mkdir -p "/usr/share/ca-certificates/$2"
		cp "$1" "/usr/share/ca-certificates/$2/$3"
		echo "$2/$3" >> /etc/ca-certificates.conf
		update-ca-certificates
	fi
}

# The hcp_common.py function 'dict_timedelta' parses a time period out of a
# JSON struct so that it can be expressed using any of 'years', 'months',
# 'weeks', 'days', 'hours', 'minutes', and/or 'seconds'. This bash version is
# similar except;
# - it takes the JSON string in $1, whereas the python version takes a python
#   dict (already converted from JSON),
# - it returns an integer number of seconds, whereas the python version
#   returns a datetime.timedelta object.
function dict_timedelta {
	thejson=$1
	# for get_element;
	#  $1 = name
	function get_element {
		x=$(echo "$thejson" | jq -r ".$1 // 0")
		echo "$x"
	}
	val=0
	val=$((val + $(get_element "years") * 365 * 24 * 60 * 60))
	val=$((val + $(get_element "months") * 28 * 24 * 60 * 60))
	val=$((val + $(get_element "weeks") * 7 * 24 * 60 * 60))
	val=$((val + $(get_element "days") * 24 * 60 * 60))
	val=$((val + $(get_element "hours") * 60 * 60))
	val=$((val + $(get_element "minutes") * 60))
	val=$((val + $(get_element "seconds")))
	echo "$val"
}

# The above stuff (apart from "set -e") is all function-definition, here we
# actually _do_ something when you source this file.
# TODO: this should be removed, and instead we should consume 'env' properties
# from the configuration.

for i in $(find / -maxdepth 1 -mindepth 1 -type d -name "install-*"); do
	add_install_path "$i"
done
