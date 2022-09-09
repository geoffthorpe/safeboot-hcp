#!/bin/bash

retries=0
pause=1
onlyenroll=
onlycreate=
VERBOSE=0
URL=
JSONPATH="$HCP_ORCHESTRATOR_JSON"

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
Usage: $PROG [OPTIONS] [names ...]

  Runs the orchestrator, to create and/or enroll TPMs. This requires a JSON
  description of the host(s) and profile(s) to use, colloquially called
  'fleet.json' (though the real file name can be anything). If 'names'
  arguments are provided, then only the correspondingly-named entries from the
  'fleet.json' will be processed, otherwise all entries are processed.

  Options:

    -h               This message
    -v               Verbose
    -e               Enroll-only (don't create any TPMs)
    -c               Create-only (don't enroll any TPMs)
    -R <num>         Number of retries before failure
        (default: $retries)
    -P <seconds>     Time between retries
        (default: $pause)
    -U <url>         Fallback URL if none specified in 'fleet.json'
        (default: $(test -n "$URL" && echo "$URL" || echo "None"))
    -J <jsonpath>    Path to 'fleet.json' file
        (default: $JSONPATH)
EOF
	exit "${1:-1}"
}

while getopts +:R:P:U:J:hvec opt; do
case "$opt" in
R)	retries="$OPTARG";;
P)	pause="$OPTARG";;
U)	URL="$OPTARG";;
J)	JSONPATH="$OPTARG";;
h)	usage 0;;
v)	((VERBOSE++)) || true;;
e)	onlyenroll=1;;
c)	onlycreate=1;;
*)	echo >&2 "Unknown option: $opt"; usage;;
esac
done
shift $((OPTIND - 1))

if ((VERBOSE > 0)); then
	cat >&2 <<EOF
Starting $PROG:
 - retries=$retries
 - pause=$pause
 - onlyenroll=$onlyenroll
 - onlycreate=$onlycreate
 - VERBOSE=$VERBOSE
 - URL=$URL
 - JSONPATH=$JSONPATH
 - #names=$#
 - {names}=$@
EOF
fi

cd /
if [[ -z $JSONPATH || ! -f $JSONPATH ]]; then
	echo "Error, JSON input not found at '$JSONPATH'" >&2
	usage
fi
if [[ -n $onlyenroll && -n $onlycreate ]]; then
	echo "Error, options -c and -e are mutually exclusive" >&2
	usage
fi

# Extract defaults (and we'll need the profile sub-struct too)
fleet_defaults=$(jq -r '.defaults // {}' $JSONPATH)
fleet_defaults_profile=$(echo "$fleet_defaults" | jq -r ".enroll_profile // {}")

# Extract fleet entry names
fleet_names=( $(jq -r '.fleet[].name' $JSONPATH) )
uniqueNum=$(printf '%s\n' "${fleet_names[@]}" | \
	awk '!($0 in seen){seen[$0];c++} END {print c}')
(( uniqueNum != ${#fleet_names[@]} )) && 
	echo "Error, duplicate fleet entries" >&2 &&
	exit 1

if ((VERBOSE > 0)); then
	cat >&2 <<EOF
fleet_defaults=$fleet_defaults
fleet_defaults_profile=$fleet_defaults_profile
fleet_names=${fleet_names[@]}
uniqueNum=$uniqueNum
EOF
fi

# This is the subroutine of do_item_tpm() which does the raw work, and which
# produces output to stdout that can ignored if it completes successfully.
raw_create_tpm()
{
	# Whenever this subshell exits, remove "tpm-temp" if it still exists.
	# Also we'll background a task soon, so clean that up too.
	mypid=0
	trap 'rm -rf $mytpm; [[ $mypid == 0 ]] || kill -9 $mypid' EXIT ERR
	mkdir "$mytpm"
	# This starts TPM creation...
	swtpm_setup --tpm2 --createek --tpmstate "$mytpm" --config /dev/null ||
		(echo "Error, TPM '$name' creation failed pt 1" && exit 1) ||
		return 1
	# ... but for obscure reasons, we have to actually _start_ the TPM for
	# the next step...
	mysocks=$(mktemp -d)
	swtpm socket --tpm2 --tpmstate dir="$mytpm" \
		--server type=unixio,path=$mysocks/tpm \
		--ctrl type=unixio,path=$mysocks/tpm.ctrl \
		--flags startup-clear &
	mypid=$!
	export TPM2TOOLS_TCTI=swtpm:path=$mysocks/tpm
	# ... and for classical reasons, we can't be 100% sure a backgrounded
	# service will be listening when we try to use it, so use a retry loop.
	waitcount=0
	until tpm2 createek -c "$mytpm/ek.ctx" -u "$mytpm/ek.pub"; do
		if [[ $((++waitcount)) -eq 10 ]]; then
			(echo "Error, TPM '$name' failed pt 2" && exit 1) ||
			return 1
		fi
		echo "Warning, TPM '$name' background init is waiting" >&2
		sleep 1
	done
	kill $mypid
	mypid=0
	# also export the PEM version of the EKpub
	tpm2 print -t TPM2B_PUBLIC -f PEM "$mytpm"/ek.pub ||
		(echo "Error, TPM '$name' creation PEM failed" >&2 && exit 1) ||
		return 1
	# Cool, move the TPM into place.
	mv "$mytpm" "$tpm_path/tpm"
}

do_item_tpm()
{
	if ! $tpm_create; then
		((VERBOSE > 0)) && echo "TPM '$name' not being created" >&2
		return 0
	fi
	if [[ -d "$tpm_path/tpm" ]]; then
		if [[ ! -f "$tpm_path/tpm/ek.pub" ]]; then
			echo "Error, TPM '$name' is missing 'ek.pub'" >&2
			return 1
		fi
		# It exists, if we're not asked to recreate, we're done
		if ! $tpm_recreate; then
			echo "TPM '$name' already exists" >&2
			return 0
		fi
		# Recreate. First, retire the existing 'tpm'->'tpm-old'
		if [[ -d "$tpm_path/old" ]]; then
			if ! rm -rf "$tpm_path/old"; then
				echo "Error, TPM '$name' recreation can't delete old" >&2
				return 1
			fi
		fi
		if ! mv "$tpm_path/tpm" "$tpm_path/old"; then
			echo "Error, TPM '$name' recreation can't backup" >&2
			return 1
		fi
	fi
	# We'll prepare a TPM in "tpm-temp" then move it to "tpm" as a final
	# (atomic) success step.
	mytpm="$tpm_path/tpm-temp"
	if [[ -d "$mytpm" ]]; then
		if ! rm -rf "$mytpm"; then
			echo "Error, TPM '$name' creation can't delete old temp" >&2
			return 1
		fi
	fi
	# The actual work is run in a subshell, in order to start a temporary
	# service and then rely on a trap to (a) kill the service if it wasn't
	# already, and (b) remove any incomplete TPM creation.
	((VERBOSE > 0)) && mytemperr=/dev/stderr || mytemperr=/dev/null
	echo "Creating TPM '$name'" >&2
	if (raw_create_tpm) > $mytemperr 2>&1; then
		echo "Successfully created TPM '$name'" >&2
		myreturn=0
	else
		echo "Error, failed to create TPM '$name'" >&2
		myreturn=1
	fi
	return $myreturn
}

# This is the subroutine of do_item_enroll() which does the raw work, and which
# produces output to stderr that can be ignored if it completes successfully.
# TODO: there's currently no control over timeouts, should probably be
# controllable via the JSON. Also, the retry loop could be pushed into
# enroll_api.py.
raw_enroll_tpm()
{
	# We're going to be talking to the Enrollment Service
	if [[ -z $enroll_hostname ]]; then
		echo "Error, TPM '$name' has no hostname for enrollment" >&2
		return 1
	fi
	if [[ -z $enroll_api ]]; then
		echo "Error, no API endpoint to enroll TPM '$name'" >&2
		return 1
	fi
	api_cmd="python3 /hcp/tools/enroll_api.py --api $enroll_api"
	api_cmd="$api_cmd --retries $retries"
	api_cmd="$api_cmd --pause $pause"
	((VERBOSE > 0)) &&
		api_cmd="$api_cmd --verbosity 2" ||
		api_cmd="$api_cmd --verbosity 0"
	if [[ -n HCP_CERTCHECKER ]]; then
		if [[ $HCP_CERTCHECKER == "none" ]]; then
			api_cmd="$api_cmd --noverify"
		else
			api_cmd="$api_cmd --cacert $HCP_CERTCHECKER"
		fi
	fi
	if [[ -n HCP_CLIENTCERT ]]; then
		api_cmd="$api_cmd --clientcert $HCP_CLIENTCERT"
	fi
	# Calculate the ekpubhash
	ekpubhash=$(openssl sha256 "$tpm_path/tpm/ek.pub" | \
		sed -e "s/^.*= //" | cut -c 1-32)
	((VERBOSE > 0)) && echo "api_cmd: $api_cmd query $ekpubhash" >&2
	# Query to see if this TPM is already enrolled
	if ! myquery=$($api_cmd query $ekpubhash); then
		echo "Error, unable to query enrollsvc ($myquery)" >&2
		return 1
	fi
	((VERBOSE > 0)) && echo "result: $myquery" >&2
	if echo "$myquery" | jq -e '.entries | length>0' > /dev/null ; then
		# If we're not asked to reenroll, that's that
		if ! $enroll_always; then
			echo "TPM '$name' already enrolled" >&2
			return 0
		fi
		echo "ERROR, reenrolling support isn't implemented yet" >&2
	fi
	# Enroll
	echo "Enrolling TPM '$name'" >&2
	((VERBOSE > 0)) &&
		echo "api_cmd: $api_cmd add --profile \"$enroll_profile\" \\" >&2 &&
		echo "        $tpm_path/tpm/ek.pub $enroll_hostname" >&2
	if ! myquery=$($api_cmd add --profile "$enroll_profile" \
				$tpm_path/tpm/ek.pub $enroll_hostname); then
		echo "Error, enrollment failure ($myquery)" >&2
		return 1
	fi
	((VERBOSE > 0)) &&
		echo "enrollment result: $myquery" >&2
	echo "TPM '$name' enrolled" >&2
}

do_item_enroll()
{
	# If we're not asked to enroll, that's that
	if ! $enroll_enroll; then
		((VERBOSE>0)) && echo "TPM '$name' not being enrolled" >&2
		return 0
	fi
	if raw_enroll_tpm; then
		echo "Successfully enrolled TPM '$name'" >&2
		myreturn=0
	else
		echo "Error, failed to enroll TPM '$name'" >&2
		myreturn=1
	fi
	return $myreturn
}

# This is the function that operates on each item of the fleet
do_item()
{
	name=$1
	((VERBOSE > 0)) && echo "do_item: $name" >&2
	item=$(jq ".fleet[] | select(.name == \"$name\")" $JSONPATH)
	# We want to "merge" the fleet item $fleet_defaults. The basic merge in
	# jq unions the fields of the two structures at the top level only,
	# preferring the right-parameter's version when both have fields of the
	# same name.
	entry=$(jq -cn "$fleet_defaults * $item")

	# Now extract the fields from the merged JSON for use by the above functions
	tpm_path=$(echo "$entry" | jq -r ".tpm_path // empty")
	[[ -n $onlyenroll ]] && tpm_create=false ||
		tpm_create=$(echo "$entry" | jq -r ".tpm_create // false")
	tpm_recreate=$(echo "$entry" | jq -r ".tpm_recreate // false")
	[[ -n $onlycreate ]] && enroll_enroll=false ||
		enroll_enroll=$(echo "$entry" | jq -r ".enroll // false")
	enroll_always=$(echo "$entry" | jq -r ".enroll_always // false")
	enroll_api=$(echo "$entry" | jq -r ".enroll_api // empty")
	if [[ -z $enroll_api ]]; then
		enroll_api="$URL"
	fi
	enroll_hostname=$(echo "$entry" | jq -r ".enroll_hostname // empty")
	enroll_profile=$(echo "$entry" | jq -r ".enroll_profile // {}")
if ((VERBOSE > 0)); then
	cat >&2 <<EOF
 - entry=$entry
 - tpm_path=$tpm_path
 - tpm_create=$tpm_create
 - tpm_recreate=$tpm_recreate
 - enroll_enroll=$enroll_enroll
 - enroll_always=$enroll_always
 - enroll_api=$enroll_api
 - enroll_hostname=$enroll_hostname
 - enroll_profile=$enroll_profile
EOF
fi
	do_item_tpm || return 1
	do_item_enroll || return 1
}

if (($# > 0)); then
	((VERBOSE > 0)) && echo "Using user-supplied entries: $@" >&2
	while (($# > 0))
	do
		do_item "$1"
		shift
	done
else
	((VERBOSE > 0)) && echo "Using JSON-supplied entries: ${fleet_names[@]}" >&2
	for item in "${fleet_names[@]}"
	do
		do_item "$item"
	done
fi

exit 0
