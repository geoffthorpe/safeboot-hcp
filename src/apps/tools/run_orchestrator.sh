#!/bin/bash

cd /
if [[ -z $HCP_ORCHESTRATOR_JSON || ! -f $HCP_ORCHESTRATOR_JSON ]]; then
	echo "Error, JSON input not found at '$HCP_ORCHESTRATOR_JSON'" >&2
	exit 1
fi

# Extract defaults (and we'll need the profile sub-struct too)
fleet_defaults=$(jq -r '.defaults // {}' $HCP_ORCHESTRATOR_JSON)
fleet_defaults_profile=$(echo "$fleet_defaults" | jq -r ".enroll_profile // {}")

# Extract fleet entry names
fleet_names=( $(jq -r '.fleet[].name' $HCP_ORCHESTRATOR_JSON) )
uniqueNum=$(printf '%s\n' "${fleet_names[@]}" | \
	awk '!($0 in seen){seen[$0];c++} END {print c}')
(( uniqueNum != ${#fleet_names[@]} )) && 
	echo "Error, duplicate fleet entries" >&2 &&
	exit 1

# Uncomment if you're debugging and getting desperate
#echo "fleet_defaults=$fleet_defaults"
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
	if ! $tpm_create; then
		return 0
	fi
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
	api_cmd="python3 /hcp/tools/enroll_api.py --api $enroll_api"
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
	# Query to see if this TPM is already enrolled
	waitcount=0
	until myquery=$($api_cmd query $ekpubhash); do
		waitcount=$((waitcount+1))
		if [[ $waitcount -eq 1 ]]; then
			echo "Warning: retrying query API '$enroll_api' $ekpubhash" >&2
		fi
		if [[ $waitcount -eq 11 ]]; then
			echo "Error: giving up" >&2
			return 1
		fi
		sleep 1
	done
	if echo "$myquery" | jq -e '.entries | length>0' >&2 ; then
		# If we're not asked to reenroll, that's that
		if ! $enroll_always; then
			echo "TPM '$name' already enrolled"
			return 0
		fi
		echo "ERROR, reenrolling support isn't implemented yet" >&2
	fi
	# Enroll
	echo "Enrolling TPM '$name'" >&2
	waitcount=0
	until myquery=$($api_cmd add --profile "$enroll_profile" \
				$tpm_path/tpm/ek.pub $enroll_hostname); do
		waitcount=$((waitcount+1))
		if [[ $waitcount -eq 1 ]]; then
			echo "Warning: retrying enroll API '$enroll_api' $ekpubhash" >&2
		fi
		if [[ $waitcount -eq 11 ]]; then
			echo "Error: giving up" >&2
			return 1
		fi
		sleep 1
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
	# We want to "merge" the entry in $2 with $fleet_defaults. The basic
	# merge in jq unions the fields of the two structures at the top level
	# only, preferring the right-parameter's version when both have fields
	# of the same name.
	entry=$(jq -cn "$fleet_defaults * $2")

	# Now extract the fields from the merged JSON for use by the above functions
	tpm_path=$(echo "$entry" | jq -r ".tpm_path // empty")
	tpm_create=$(echo "$entry" | jq -r ".tpm_create // false")
	tpm_recreate=$(echo "$entry" | jq -r ".tpm_recreate // false")
	enroll_enroll=$(echo "$entry" | jq -r ".enroll // false")
	enroll_always=$(echo "$entry" | jq -r ".enroll_always // false")
	enroll_api=$(echo "$entry" | jq -r ".enroll_api // empty")
	enroll_hostname=$(echo "$entry" | jq -r ".enroll_hostname // empty")
	enroll_profile=$(echo "$entry" | jq -r ".enroll_profile // {}")
	# Uncomment if you're debugging and getting desperate
	#echo "name=$name"
	#echo "entry=$entry"
	#echo "tpm_path=$tpm_path"
	#echo "tpm_create=$tpm_create"
	#echo "tpm_recreate=$tpm_recreate"
	#echo "enroll_enroll=$enroll_enroll"
	#echo "enroll_always=$enroll_always"
	#echo "enroll_api=$enroll_api"
	#echo "enroll_hostname=$enroll_hostname"
	#echo "enroll_profile=$enroll_profile"
	do_item_tpm || return 1
	do_item_enroll || return 1
}

for item in "${fleet_names[@]}"
do
	entry=$(jq ".fleet[] | select(.name == \"$item\")" $HCP_ORCHESTRATOR_JSON)
	do_item $item "$entry"
done

exit 0
