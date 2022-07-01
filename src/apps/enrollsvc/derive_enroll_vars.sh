#!/bin/bash

# This is sourced into op_add.sh and provides the function "derive_enroll_vars"
# that is called once. The purpose is to use whatever ENROLL_* environment has
# been established based on the server's JSON (enrollsvc.json) and the JSON
# sent from the client (the "profile" element of the request), and derive some
# other ENROLL_* variables from those. Once we're done, parameter-expansion is
# performed on the merged JSON using these ENROLL_* settings, so these extra
# ENROLL_* variables can be harnessed from there.

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

	# ENROLL_HOSTNAME2DC
	#   - if ENROLL_HOSTNAME="bob.hcphacking.xyz"
	#   - then ENROLL_HOSTNAME2DC="DC=bob,DC=hcphacking,DC=xyz"
	export ENROLL_HOSTNAME2DC=$(localname2dc "$ENROLL_HOSTNAME")

	# ENROLL_DOMAIN2DC
	#   - if ENROLL_DOMAIN="hcphacking.xyz"
	#   - then ENROLL_DOMAIN2DC="DC=hcphacking,DC=xyz"
	export ENROLL_DOMAIN2DC=$(localname2dc "$ENROLL_DOMAIN")

}
