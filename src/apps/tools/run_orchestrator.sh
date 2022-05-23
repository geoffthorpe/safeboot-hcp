#!/bin/bash

. /hcp/common/hcp.sh

set -e

# Print the base configuration
echo "Running '$0'" >&2
show_hcp_env >&2

if [[ ! -d "/safeboot/sbin" ]]; then
	echo "Error, /safeboot/sbin is not present" >&2
	exit 1
fi
export PATH=$PATH:/safeboot/sbin
echo "Adding /safeboot/sbin to PATH" >&2

if [[ -d "/install/bin" ]]; then
	export PATH=$PATH:/install/bin
	echo "Adding /install/sbin to PATH" >&2
fi

if [[ -d "/install/lib" ]]; then
	export LD_LIBRARY_PATH=/install/lib:$LD_LIBRARY_PATH
	echo "Adding /install/lib to LD_LIBRARY_PATH" >&2
	if [[ -d /install/lib/python3/dist-packages ]]; then
		export PYTHONPATH=/install/lib/python3/dist-packages:$PYTHONPATH
		echo "Adding /install/lib/python3/dist-packages to PYTHONPATH" >&2
	fi
fi

cd /
if [[ -z $HCP_ORCHESTRATOR_JSON || ! -f $HCP_ORCHESTRATOR_JSON ]]; then
	echo "Error, JSON input not found at '$HCP_ORCHESTRATOR_JSON'" >&2
	exit 1
fi

# Extract defaults (TBD: can this all be done with a single jq call/pass?)
def_tpm_create=$(jq -r '.tpm_defaults.create' $HCP_ORCHESTRATOR_JSON)
def_tpm_recreate=$(jq -r '.tpm_defaults.recreate' $HCP_ORCHESTRATOR_JSON)
def_enroll_api=$(jq -r '.enroll_defaults.api' $HCP_ORCHESTRATOR_JSON)
def_enroll_profile=$(jq -r '.enroll_defaults.profile' $HCP_ORCHESTRATOR_JSON)
def_enroll_enroll=$(jq -r '.enroll_defaults.enroll' $HCP_ORCHESTRATOR_JSON)
def_enroll_reenroll=$(jq -r '.enroll_defaults.reenroll' $HCP_ORCHESTRATOR_JSON)

# Extract fleet entry names
fleet_names=( $(jq -r '.fleet[].name' $HCP_ORCHESTRATOR_JSON) )
uniqueNum=$(printf '%s\n' "${fleet_names[@]}" | \
	awk '!($0 in seen){seen[$0];c++} END {print c}')
(( uniqueNum != ${#fleet_names[@]} )) && 
	echo "Error, duplicate fleet entries" >&2 &&
	exit 1

# Uncomment if you're debugging and getting desperate
#echo "def_tpm_create=$def_tpm_create"
#echo "def_tpm_recreate=$def_tpm_recreate"
#echo "def_enroll_api=$def_enroll_api"
#echo "def_enroll_profile=$def_enroll_profile"
#echo "def_enroll_enroll=$def_enroll_enroll"
#echo "def_enroll_reenroll=$def_enroll_reenroll"
#echo "fleet_names=${fleet_names[@]}"
#echo "uniqueNum=$uniqueNum"

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
		echo "Warning, TPM '$name' background init is waiting"
		sleep 1
	done
	kill $mypid
	mypid=0
	# also export the PEM version of the EKpub
	tpm2 print -t TPM2B_PUBLIC -f PEM "$mytpm"/ek.pub ||
		(echo "Error, TPM '$name' creation PEM failed" && exit 1) ||
		return 1
	# Cool, move the TPM into place.
	mv "$mytpm" "$tpm_path/tpm"
}

do_item_tpm()
{
	if [[ -d "$tpm_path/tpm" ]]; then
		if [[ ! -f "$tpm_path/tpm/ek.pub" ]]; then
			echo "Error, TPM '$name' is missing 'ek.pub'" >&2
			return 1
		fi
		# It exists, if we're not asked to recreate, we're done
		if ! $tpm_recreate; then
			echo "TPM '$name' already exists"
			return 0
		fi
		# Recreate. First, retire the existing 'tpm'->'tpm-old'
		if [[ -d "$tpm_path/old" ]]; then
			if ! rm -rf "$tpm_path/old"; then
				echo "Error, TPM '$name' recreation can't delete old" >&2
				return 1
			fi
		fi
		if ! mv "$tpm_path" "$tpm_path/old"; then
			echo "Error, TPM '$name' recreation can't backup" >&2
			return 1
		fi
	else
		# It doesn't exist. If we're not ask to create, we're done
		if ! $tpm_create; then
			echo "Error, TPM '$name' doesn't exist" >&2
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
	mytempdir=$(mktemp -d)
	echo "Creating TPM '$name'"
	if (raw_create_tpm) > $mytempdir/output 2>&1; then
		echo "Successfully created TPM '$name'"
		myreturn=0
	else
		echo "Error, failed to create TPM '$name', debug output;" >&2
		cat $mytempdir/output >&2
		myreturn=1
	fi
	rm -rf $mytempdir
	return $myreturn
}

# This is the subroutine of do_item_enroll() which does the raw work, and which
# produces output to stderr that can be ignored if it completes successfully.
# TODO: there's currently no control over timeouts, should probably be
# controllable via the JSON. Also, the retry loop could be pushed into
# enroll_api.py.
raw_enroll_tpm()
{
	# If we're not asked to enroll, that's that
	if ! $enroll_enroll; then
		echo "TPM '$name' not being enrolled"
		return 0
	fi
	# Otherwise, we're going to be talking to the Enrollment Service
	if [[ -z $enroll_hostname ]]; then
		echo "Error, TPM '$name' has no hostname for enrollment" >&2
		return 1
	fi
	if [[ -z $enroll_api ]]; then
		echo "Error, no API endpoint to enroll TPM '$name'" >&2
		return 1
	fi
	# Calculate the ekpubhash
	ekpubhash=$(openssl sha256 "$tpm_path/tpm/ek.pub" | \
		sed -e "s/^.*= //" | cut -c 1-32)
	# Query to see if this TPM is already enrolled
	waitsecs=0
	waitinc=3
	waitcount=0
	until myquery=$(python3 /hcp/tools/enroll_api.py \
				--api "$enroll_api" \
				query $ekpubhash); do
		if [[ $((++waitcount)) -eq 10 ]]; then
			echo "Error, failed query API '$enroll_api' $ekpubhash" >&2
			return 1
		fi
		sleep $((waitsecs+=waitinc))
		echo "Warning, retrying query API '$enroll_api' in ${waitsecs}s" >&2
	done
	if echo "$myquery" | jq -e '.entries | length>0' >&2 ; then
		# If we're not asked to reenroll, that's that
		if ! $enroll_reenroll; then
			echo "TPM '$name' already enrolled"
			return 0
		fi
		echo "ERROR, reenrolling support isn't implemented yet" >&2
	fi
	# Enroll
	echo "Enrolling TPM '$name'" >&2
	waitsecs=0
	waitinc=3
	waitcount=0
	until myquery=$(python3 /hcp/tools/enroll_api.py \
				--api "$enroll_api" \
				add \
				--profile "$enroll_profile" \
				$tpm_path/tpm/ek.pub $enroll_hostname); do
		if [[ $((++waitcount)) -eq 10 ]]; then
			echo "Error, failed enroll API '$enroll_api'" >&2
			return 1
		fi
		sleep $((waitsecs+=waitinc))
		echo "RETRYING in ${waitsecs}s\n..."
	done
	echo "TPM '$name' enrolled"
}

do_item_enroll()
{
	# The actual work is deferred to a subroutine with its stderr captured,
	# so that it's only displayed if the routine isn't successful. We allow
	# stdout to pass through, though.
	mytemperr=$(mktemp)
	if raw_enroll_tpm 2> $mytemperr; then
		myreturn=0
	else
		echo "Error, failed to enroll TPM '$name', debug output;" >&2
		cat $mytemperr >&2
		myreturn=1
	fi
	rm $mytemperr
	return $myreturn
}

# This is the function that operates on each item of the fleet
do_item()
{
	name=$1
	entry=$2
	tpm_path=$(echo "$entry" | jq -r ".tpm.path // empty")
	tpm_create=$(echo "$entry" | jq -r ".tpm.create // empty")
	tpm_recreate=$(echo "$entry" | jq -r ".tpm.recreate // empty")
	enroll_hostname=$(echo "$entry" | jq -r ".enroll.hostname // empty")
	enroll_api=$(echo "$entry" | jq -r ".enroll.api // empty")
	enroll_profile=$(echo "$entry" | jq -r ".enroll.profile // empty")
	enroll_enroll=$(echo "$entry" | jq -r ".enroll.enroll // empty")
	enroll_reenroll=$(echo "$entry" | jq -r ".enroll.reenroll // empty")
	: "${tpm_path:=$def_tpm_path}"
	: "${tpm_create:=$def_tpm_create}"
	: "${tpm_recreate:=$def_tpm_recreate}"
	: "${enroll_hostname:=$def_enroll_hostname}"
	: "${enroll_api:=$def_enroll_api}"
	: "${enroll_profile:=$def_enroll_profile}"
	: "${enroll_enroll:=$def_enroll_enroll}"
	: "${enroll_reenroll:=$def_enroll_reenroll}"
	# Uncomment if you're debugging and getting desperate
	#echo "name=$name"
	#echo "entry=$entry"
	#echo "tpm_path=$tpm_path"
	#echo "tpm_create=$tpm_create"
	#echo "tpm_recreate=$tpm_recreate"
	#echo "enroll_hostname=$enroll_hostname"
	#echo "enroll_api=$enroll_api"
	#echo "enroll_profile=$enroll_profile"
	#echo "enroll_enroll=$enroll_enroll"
	#echo "enroll_reenroll=$enroll_reenroll"
	do_item_tpm || return 1
	do_item_enroll || return 1
}

for item in "${fleet_names[@]}"
do
	entry=$(jq ".fleet[] | select(.name == \"$item\")" $HCP_ORCHESTRATOR_JSON)
	do_item $item "$entry"
done

exit 0
