#!/bin/bash

source /hcp/common/hcp.sh

JSONPATH=$(hcp_config_extract ".orchestrator.fleet")

retries=0
pause=1
timeout=600
option_create=
option_destroy=
option_enroll=
option_reenroll=
option_unenroll=
option_janitor=
VERBOSE=0
URL=

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
  If -e, -c, -u, -r, or -d are provided, they stipulate the action(s) that
  should take place for each of the fleet entries they apply to.
  If -j is provided, the enrollment service's "janitor" API will be called,
  it is not specific to any fleet entry.

  Options:

    -h               This message
    -v               Verbose
    -c               Create TPM instance if it doesn't exist
    -d               Destroy TPM instance if it exists
    -e               Enroll TPM if it isn't enrolled
    -r               Re-enroll TPM if it is enrolled
    -u               Unenroll TPM if it is enrolled
    -j               Request that the enrollsvc run its 'janitor'
    -R <num>         Number of retries before failure
        (default: $retries)
    -P <seconds>     Time between retries
        (default: $pause)
    -T <seconds>     Timeout
        (default: $timeout)
    -U <url>         Fallback URL if none specified in 'fleet.json'
        (default: $(test -n "$URL" && echo "$URL" || echo "None"))
    -J <jsonpath>    Path to 'fleet.json' file
        (default: $JSONPATH)
EOF
	exit "${1:-1}"
}

while getopts +:R:P:T:U:J:hvcderuj opt; do
case "$opt" in
R)	retries="$OPTARG";;
P)	pause="$OPTARG";;
T)	timeout="$OPTARG";;
U)	URL="$OPTARG";;
J)	JSONPATH="$OPTARG";;
h)	usage 0;;
v)	((VERBOSE++)) || true;;
c)	option_create=1;;
d)	option_destroy=1;;
e)	option_enroll=1;;
r)	option_reenroll=1;;
u)	option_unenroll=1;;
j)	option_janitor=1;;
*)	echo >&2 "Unknown option: $opt"; usage;;
esac
done
shift $((OPTIND - 1))

# Shorthand so that we don't have to do VERBOSE comparisons all the time. Of
# course this is less efficient because the output processing is performed even
# when it's destined for /dev/null, but we're in bash and shelling out to
# swtpm, so it's not like we'll notice the difference.
((VERBOSE > 0)) && out1=/dev/stderr || out1=/dev/null
((VERBOSE > 1)) && out2=/dev/stderr || out2=/dev/null

cat >$out1 <<EOF
Starting $PROG:
 - retries=$retries
 - pause=$pause
 - timeout=$timeout
 - option_create=$option_create
 - option_destroy=$option_destroy
 - option_enroll=$option_enroll
 - option_unenroll=$option_unenroll
 - VERBOSE=$VERBOSE
 - URL=$URL
 - JSONPATH=$JSONPATH
 - #names=$#
 - {names}=$@
EOF

cd /
if [[ -z $JSONPATH || ! -f $JSONPATH ]]; then
	echo "Error, JSON input not found at '$JSONPATH'" >&2
	usage
fi
if [[ -n $option_create ]]; then
	if [[ -n $option_destroy || -n $option_unenroll ]]; then
		echo "Error, option -c is incompatible with -d/-u" >&2
		usage
	fi
elif [[ -n $option_destroy ]]; then
	if [[ -n $option_enroll ]]; then
		echo "Error, option -d is incompatible with -e" >&2
		usage
	fi
elif [[ -n $option_enroll ]]; then
	if [[ -n $option_unenroll ]]; then
		echo "Error, option -e is incompatible with -u" >&2
		usage
	fi
fi

# Extract defaults (and we'll need the profile sub-struct too)
echo "JSONPATH=$JSONPATH" > $out2
echo "content(JSONPATH)=$(cat $JSONPATH)" > $out2
fleet_defaults=$(jq -r '.defaults // {}' $JSONPATH)
echo "fleet_defaults=$fleet_defaults" > $out1
fleet_defaults_profile=$(echo "$fleet_defaults" | jq -r ".enroll_profile // {}")
echo "fleet_defaults_profile=$fleet_defaults_profile" > $out1

# Extract fleet entry names
fleet_names=( $(jq -r '.fleet[].name' $JSONPATH) )
echo "fleet_names=${fleet_names[@]}" > $out1
uniqueNum=$(printf '%s\n' "${fleet_names[@]}" | \
	awk '!($0 in seen){seen[$0];c++} END {print c}')
echo "uniqueNum=$uniqueNum" > $out1
(( uniqueNum != ${#fleet_names[@]} )) && 
	echo "Error, duplicate fleet entries" >&2 &&
	exit 1


# Bash doesn't do return values, so we output "false" or "true" and rely on the
# fact that the caller can treat that output as an executable command that
# gives the required status. Eg.
#    does_it_exist=$(raw_tpm_exists)
#    if $does_it_exist; then
#        [...]
#    fi
raw_tpm_exists()
{
	echo "raw_tpm_exists: starting" > $out2
	if [[ -f "$tpm_path/tpm/ek.pub" ]]; then
		echo "raw_tpm_exists: returning true" > $out2
		echo true
	else
		if [[ -d "$tpm_path/tpm" ]]; then
			echo "raw_tpm_exists: WARNING: removing stale directory" >&2
			rm -rf "$tpm_path/tpm"
		fi
		echo "raw_tpm_exists: returning false" > $out2
		echo false
	fi
	return 0
}

# The function runs itself in a subshell (because it uses "trap" as a
# destructor)
raw_tpm_create()
{
	echo "raw_tpm_create: starting (subshell)" > $out2
(
	# Whenever this subshell exits, remove "tpm-temp" if it still exists.
	# Also we'll background a task soon, so clean that up too.
	mypid=0
	tt="$tpm_path/tpm-temp"
#	trapline=$(cat - <<EOF
#[[ -z "$tt" ]] || rm -rf "$tt"
#[[ $mypid == 0 ]] || kill -9 $mypid
#EOF
#)
	trap '[[ -z "$tt" ]] || rm -rf "$tt"; [[ $mypid == 0 ]] || kill -9 $mypid' EXIT
	echo "raw_tpm_create: set EXIT trap with '$trapline'" > $out2
	mkdir "$tt"
	# This starts TPM creation...
	echo "raw_tpm_create: initializing tpmstate" > $out2
	swtpm_setup --tpm2 --createek --tpmstate "$tt" --config /dev/null ||
		(echo "Error, TPM '$name' creation failed pt 1" && exit 1) ||
		return 1
	# ... but for obscure reasons, we have to actually _start_ the TPM for
	# the next step...
	echo "raw_tpm_create: launching temp swtpm instance" > $out2
	mysocks=$(mktemp -d)
	swtpm socket --tpm2 --tpmstate dir="$tt" \
		--server type=unixio,path=$mysocks/tpm \
		--ctrl type=unixio,path=$mysocks/tpm.ctrl \
		--flags startup-clear &
	mypid=$!
	export TPM2TOOLS_TCTI=swtpm:path=$mysocks/tpm
	# ... and for classical reasons, we can't be 100% sure a backgrounded
	# service will be listening by the time we try to use it, so use a
	# retry loop.
	echo "raw_tpm_create: entering retry loop for 'createek'" > $out2
	waitcount=0
	until tpm2 createek -c "$tt/ek.ctx" -u "$tt/ek.pub"; do
		if [[ $((++waitcount)) -eq 10 ]]; then
			echo "Error, TPM '$name' failed pt 2" >&2
			return 1
		fi
		echo "Warning, TPM '$name' background init is waiting" > $out1
		sleep 1
	done
	echo "raw_tpm_create: killing temp swtpm instance" > $out2
	kill $mypid
	mypid=0
	# also export the PEM version of the EKpub
	echo "raw_tpm_create: converting to PEM" > $out2
	tpm2 print -t TPM2B_PUBLIC -f PEM "$tt/ek.pub" ||
		(echo "Error, TPM '$name' creation PEM failed" >&2 && exit 1) ||
		return 1
	# Cool, move the TPM into place.
	echo "raw_tpm_create: moving finalized TPM into place" > $out2
	mv "$tt" "$tpm_path/tpm"
	echo "raw_tpm_create: done" > $out2
)
}

raw_tpm_destroy()
{
	echo "raw_tpm_destroy: starting" > $out2
	rm -rf "$tpm_path/tpm"
	echo "raw_tpm_destroy: done" > $out2
}

api_prerequisites()
{
	echo "api_prerequisites: starting" > $out2
	if [[ -n $api_cmd ]]; then
		echo "api_prerequisites: cached, already done" > $out2
	fi
	if [[ -z $enroll_api ]]; then
		echo "Error, no API endpoint to enroll TPM '$name'" >&2
		return 1
	fi
	echo "api_prerequisites: building api_cmd" > $out2
	api_cmd="python3 /hcp/tools/enroll_api.py --api $enroll_api"
	api_cmd="$api_cmd --retries $retries"
	api_cmd="$api_cmd --pause $pause"
	api_cmd="$api_cmd --timeout $timeout"
	((VERBOSE > 0)) &&
		api_cmd="$api_cmd --verbosity 2" ||
		api_cmd="$api_cmd --verbosity 0"
	if [[ -f /enrollcertchecker/CA.cert ]]; then
		api_cmd="$api_cmd --cacert /enrollcertchecker/CA.cert"
	else
		api_cmd="$api_cmd --noverify"
	fi
	if [[ -f /enrollclient/client.pem ]]; then
		api_cmd="$api_cmd --clientcert /enrollclient/client.pem"
	fi
	echo "api_prerequisites: api_cmd=$api_cmd" > $out2
}

# Similar semantics to raw_tpm_exists()
raw_tpm_enrolled()
{
	echo "raw_tpm_enrolled: starting" > $out2
	api_prerequisites
	# We're going to be talking to the Enrollment Service
	echo "raw_tpm_enrolled: api_cmd: $api_cmd query $ekpubhash" > $out2
	# Query to see if this TPM is already enrolled
	if ! myquery=$($api_cmd query $ekpubhash); then
		echo "Error, unable to query enrollsvc ($myquery)" >&2
		return 1
	fi
	echo "raw_tpm_enrolled: result: $myquery" > $out2
	if echo "$myquery" | jq -e '.entries | length>0' > /dev/null ; then
		echo "raw_tpm_enrolled: returning true" > $out2
		echo true
	else
		echo "raw_tpm_enrolled: returning false" > $out2
		echo false
	fi
	echo "raw_tpm_enrolled: done" > $out2
	return 0
}

# This does the raw work of enrolling a TPM.
raw_tpm_enroll()
{
	echo "raw_tpm_enroll: starting" > $out2
	api_prerequisites
	# Enroll
	echo "Enrolling TPM '$name'"
	if [[ -z $enroll_hostname ]]; then
		echo "Error, TPM '$name' has no hostname for enrollment" >&2
		return 1
	fi
	echo "raw_tpm_enroll: api_cmd: $api_cmd add --profile \"$enroll_profile\" \\" > $out2
	echo "                $tpm_path/tpm/ek.pub $enroll_hostname" > $out2
	if ! myquery=$($api_cmd add --profile "$enroll_profile" \
				$tpm_path/tpm/ek.pub $enroll_hostname); then
		echo "Error, enrollment failure ($myquery)" >&2
		return 1
	fi
	echo "raw_tpm_enroll: result: $myquery" > $out2
	echo "TPM '$name' enrolled"
	echo "raw_tpm_enroll: done" > $out2
}

raw_tpm_reenroll()
{
	echo "raw_tpm_reenroll: starting" > $out2
	api_prerequisites
	echo "Re-enrolling TPM '$name'"
	echo "raw_tpm_reenroll: api_cmd: $api_cmd reenroll $ekpubhash" > $out2
	if ! myresult=$($api_cmd reenroll $ekpubhash); then
		echo "Error, re-enrollment failure ($myresult)" >&2
		return 1
	fi
	echo "raw_tpm_reenroll: result: $myresult" > $out2
	echo "TPM '$name' re-enrolled"
	echo "raw_tpm_reenroll: done" > $out2
}

raw_tpm_unenroll()
{
	echo "raw_tpm_unenroll: starting" > $out2
	api_prerequisites
	echo "Unenrolling TPM '$name'"
	echo "raw_tpm_unenroll: api_cmd: $api_cmd delete $ekpubhash" > $out2
	if ! myresult=$($api_cmd delete $ekpubhash); then
		echo "Error, unenrollment failure ($myresult)" >&2
		return 1
	fi
	echo "raw_tpm_unenroll: result: $myresult" > $out2
	echo "TPM '$name' unenrolled"
	echo "raw_tpm_unenroll: done" > $out2
}

raw_janitor()
{
	echo "raw_janitor: starting" > $out2
	api_prerequisites
	echo "Running enrollsvc's 'janitor'"
	echo "raw_janitor: api_cmd: $api_cmd janitor" > $out2
	if ! myresult=$($api_cmd janitor); then
		echo "Error, janitor failure ($myresult)" >&2
		return 1
	fi
	echo "raw_janitor: result: $myresult" > $out2
	echo "'janitor' completed"
	echo "raw_janitor: done" > $out2
}

# This is the function that operates on each item of the fleet
do_item()
{
	echo "do_item: starting" > $out2
	name=$1
	matched=false
	echo "do_item: assuming matched=false" > $out2
	for (( i=0; i<${#fleet_names[@]}; i++ )); do
		if [[ $name == ${fleet_names[$i]} ]]; then
			echo "do_item: found a matching entry for '$name'" > $out2
			matched=true
		fi
	done
	if ! $matched; then
		echo "Error, '$name' is not a fleet entry" >&2
		return 1
	fi
	item=$(jq ".fleet[] | select(.name == \"$name\")" $JSONPATH)
	echo "do_item: item=$item" > $out2
	# We want to "merge" the fleet item $fleet_defaults. The basic merge in
	# jq unions the fields of the two structures at the top level only,
	# preferring the right-parameter's version when both have fields of the
	# same name.
	entry=$(jq -cn "$fleet_defaults * $item")
	echo "do_item: entry=$entry" > $out2

	# Now extract the fields from the merged JSON for use by the above functions
	tpm_path=$(echo "$entry" | jq -r ".tpm_path // empty")
	tpm_create=$(echo "$entry" | jq -r ".tpm_create // false")
	tpm_enroll=$(echo "$entry" | jq -r ".tpm_enroll // false")
	enroll_api=$(echo "$entry" | jq -r ".enroll_api // empty")
	if [[ -z $enroll_api ]]; then
		enroll_api="$URL"
	fi
	enroll_hostname=$(echo "$entry" | jq -r ".enroll_hostname // empty")
	enroll_profile=$(echo "$entry" | jq -r ".enroll_profile // {}")
	cat > $out2 <<EOF
 - entry=$entry
 - tpm_path=$tpm_path
 - tpm_create=$tpm_create
 - tpm_enroll=$tpm_enroll
 - enroll_api=$enroll_api
 - enroll_hostname=$enroll_hostname
 - enroll_profile=$enroll_profile
EOF
	check_exists=$(raw_tpm_exists)
	echo " - check_exists=$check_exists" > $out2
	if $check_exists; then
		desc="exists"
	else
		desc="doesn't exist"
	fi
	if $check_exists; then
		# Pre-compute the ekpubhash for this TPM
		ekpubhash=$(openssl sha256 "$tpm_path/tpm/ek.pub" | \
			sed -e "s/^.*= //")
		echo "do_item: ekpubhash=$ekpubhash" > $out2
		# If know how to hit the emgmt API, see if the TPM is enrolled
		if [[ -n $enroll_api ]]; then
			check_enrolled=$(raw_tpm_enrolled)
			echo " - check_enrolled=$check_enrolled" > $out2
			if $check_enrolled; then
				desc="$desc, enrolled"
			else
				desc="$desc, not enrolled"
			fi
		fi
	fi
	echo "Processing entry: $name ($desc)"
	# We attempt whichever of the four possible actions are selected, in
	# lifecycle order (to cater for whichever combinations we allow the
	# caller to try).
	if [[ -n $option_create ]]; then
		if $check_exists; then
			echo "    create: TPM already exists"
		else
			echo "do_item: creating TPM;" > $out2
			if ! raw_tpm_create > $out2 2>&1; then
				echo "Error, failed to create TPM" >&2
				return 1
			fi
			echo "    create: TPM created successfully"
			check_exists=true
			check_enrolled=false
		fi
	fi
	if [[ -n $option_enroll && -n $enroll_api ]] && $check_exists; then
		if $check_enrolled; then
			echo "    enroll: TPM already enrolled"
		else
			echo "do_item: enrolling TPM;" > $out2
			if ! raw_tpm_enroll > $out2 2>&1; then
				echo "Error, failed to enroll TPM" >&2
				return 1
			fi
			echo "    enroll: TPM enrolled successfully"
			check_enrolled=true
		fi
	fi
	if [[ -n $option_reenroll && -n $enroll_api ]] && $check_exists; then
		if ! $check_enrolled; then
			echo "    re-enroll: TPM not enrolled"
		else
			echo "do_item: re-enrolling TPM;" > $out2
			if ! raw_tpm_reenroll > $out2 2>&1; then
				echo "Error, failed to re-enroll TPM" >&2
				return 1
			fi
			echo "    re-enroll: TPM re-enrolled successfully"
		fi
	fi
	if [[ -n $option_unenroll && -n $enroll_api ]] && $check_exists; then
		if ! $check_enrolled; then
			echo "    unenroll: TPM not enrolled"
		else
			echo "do_item: unenrolling TPM;" > $out2
			if ! raw_tpm_unenroll > $out2 2>&1; then
				echo "Error, failed to unenroll TPM" >&2
				return 1
			fi
			echo "    unenroll: TPM unenrolled successfully"
			check_enrolled=false
		fi
	fi
	if [[ -n $option_destroy ]]; then
		if ! $check_exists; then
			echo "    destroy: TPM doesn't exist"
		else
			echo "do_item: destroying TPM;" > $out2
			if ! raw_tpm_destroy > $out2 2>&1; then
				echo "Error, failed to destroy TPM" >&2
				return 1
			fi
			echo "    destroy: TPM destroyed successfully"
			check_exists=false
		fi
	fi
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

if [[ -n $option_janitor ]]; then
	echo "running 'janitor';" > $out2
	if ! raw_janitor > $out2 2>&1; then
		echo "Error, failed to run enrollsvc 'janitor'" >&2
		exit 1
	fi
	echo "    janitor ran successfully"
fi

exit 0
