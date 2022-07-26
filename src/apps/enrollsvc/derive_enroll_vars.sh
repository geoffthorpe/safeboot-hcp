#!/bin/bash

# This is sourced into op_add.sh and provides the function "derive_enroll_vars"
# that is called once. The purpose is to post-process the JSON that has already
# reconciled the server's and client's inputs, in order to derive some specific
# ENROLL_* variables from the existing ones. Once we're done,
# parameter-expansion is performed on the merged JSON using these ENROLL_*
# settings, so these extra ENROLL_* variables can be harnessed from there.

function localname2dc {
	local input=$1
	local output=""
	while [[ -n $input ]]; do
		local next=$(echo "$input" | sed -e "s/\..*$//")
		input=$(echo "$input" | sed -e "s/^[^\.]*\.*//")
		[[ -z $output ]] || output="$output,"
		output="${output}DC=$next"
	done
	echo "$output"
}

function derive_enroll_vars {
	local myjson=$(cat - | jq -cS)
	local myhostname=$(echo "$myjson" | jq -r '.__env.ENROLL_HOSTNAME // empty')
	local mydomain=$(echo "$myjson" | jq -r '.__env.ENROLL_DOMAIN // empty')

	if [[ -n $myhostname ]]; then
		# ENROLL_HOSTNAME2DC
		#   - if ENROLL_HOSTNAME="bob.hcphacking.xyz"
		#   - then ENROLL_HOSTNAME2DC="DC=bob,DC=hcphacking,DC=xyz"
		myhostname2dc=$(localname2dc "$myhostname")
		local toinsert="{ \"__env\": { \"ENROLL_HOSTNAME2DC\": \"$myhostname2dc\" } }"
		myjson=$(jq -cnS "$myjson * $toinsert")
	fi

	if [[ -n $mydomain ]]; then
	# ENROLL_DOMAIN2DC
	#   - if ENROLL_DOMAIN="hcphacking.xyz"
	#   - then ENROLL_DOMAIN2DC="DC=hcphacking,DC=xyz"
		mydomain2dc=$(localname2dc "$mydomain")
		local toinsert="{ \"__env\": { \"ENROLL_DOMAIN2DC\": \"$mydomain2dc\" } }"
		myjson=$(jq -cnS "$myjson * $toinsert")
	fi
	echo "$myjson"
}
