#!/bin/bash
# vim:set noexpandtab tabstop=8:

# HCP JSON and parameter-expansion routines

# If undefined, we use an external program "param_expand" to perform a single
# pass of parameter-expansion.
export HJS_USE_PARAM_EXPAND=1

# hjs_valid_key()
#
# The key-value pairs used for parameter-expansion require keys to be formed
# only of alphanumeric and underscore characters.
function hjs_valid_key {
	validchars="[A-Za-z0-9_]"
	regexpression="^$validchars$validchars*\$"
	if echo "$1" | egrep "$regexpression" - > /dev/null 2>&1; then
		# Good
		return 0
	fi
	# Bad
	return 1
}

# hjs_check_maxsize()
#
# To avoid "decompression bomb" type issues with expansion, we run this function
# against all strings of interest to check that none of them have a length that
# exceeds a certain acceptability threshold.
function hjs_check_maxsize {
	if [[ ${#1} -gt $2 ]]; then
		echo "Error, encountered string exceeding length: $2" >&2
		exit 1
	fi
}

# hjs_from_path()
#
# When extracting values from a JSON, we use a "path". Eg. "foo" refers to an
# element at the top-level of a JSON struct, whereas "some.path.to.foo" means
# the field is deeper down. However, when trying to insert values to a
# particular point in a JSON hierarchy, that path form isn't immediately
# useful, instead we need it in the form of a (possibly-nested) JSON object so
# that can be "added" using jq's "+" operator (or merged using the "*"
# operator).
#
# Eg. rather than trying to insert <value> at "some.path.to.foo", we add;
# { "some": { "path": { "to": { "foo": <value> } } } }
#
# This function does that conversion. By default, the value that is to be coded
# into a nested JSON object is read from stdin (see -i).
#
# NOTE: THIS ONLY SUPPORTS THE CASE WHERE <value> IS ITSELF A JSON STRUCT! I.e.
# strings or arrays probably won't work, due to escapes and what-not; the value
# is assumed to start with "{" and end with "}".
#
# Note: this always the path to represent a field somewhere within the
# structure, but it raises the question of how to refer to the the top-level
# JSON object itself. If you extrapolate logically from how paths work at
# lower-layers, then the path to the top-level would have zero dot-separated
# components in it (and have -1 dots)! We handle this degenerate case with the
# path ".". I.e. remembering that <value> is itself a JSON struct, then
# inserting it at path ".", gives <value> itself! I.e. the identity operator.
#
# Arguments:
#
# -i <file>
#   The value to be encoded is read from the given file, instead of stdin.
# -o <file>
#   The JSON with the value at the appropriate path is written to this file,
#   instead of stdout.
# -j <jsonpath>  <== required
#   The dot-separated path to place the value inside the JSON output.

function hjs_from_path {
	local inputfile
	local outputfile
	local jpath
	local input
	while [[ $# -gt 0 ]]; do
		arg=$1
		shift
		case $arg in 
		-i)
			if [[ -n $inputfile ]]; then
				echo "Error, -i specified more than once" >&2
				exit 1
			fi
			inputfile=$1
			if [[ ! -f $inputfile ]]; then
				echo "Error, input file doesn't exist: $inputfile" >&2
				exit 1
			fi
			;;
		-o)
			if [[ -n $outputfile ]]; then
				echo "Error, -o specified more than once" >&2
				exit 1
			fi
			outputfile=$1
			;;
		-j)
			if [[ -n $jpath ]]; then
				echo "Error, -j specified more than once" >&2
				exit 1
			fi
			jpath=$1
			;;
		*)
			echo "Error, unrecognized argument: $arg" >&2
			exit 1
			;;
		esac
		shift
	done

	# Read the input and confirm it's valid JSON
	[[ -n $inputfile ]] || inputfile=-
	if ! input=$(cat $inputfile | jq -c 2> /dev/null); then
		echo "Error, invalid JSON" >&2
		exit 1
	fi

	if [[ -z $jpath ]]; then
		echo "Error, no JSON path specified" >&2
		exit 1
	fi

# Bypass in the degenerate case. Negative indent for readability
if [[ $jpath != "." ]]; then

	# Decompose jpath
	mypath=( $(IFS=. mypath=( $(echo $jpath) ) && echo "$mypath"))
	# Loop to construct nested output
	prefix=""
	postfix=""
	for i in ${mypath[@]}; do
		if ! hjs_valid_key "$i"; then
			echo "Error, invalid step in JSON path: $i" >&2
			exit 1
		fi
		prefix="$prefix{ \"$i\": "
		postfix="$postfix }"
	done
	# Now glue it together with the input JSON (the value)
	input="$prefix$input$postfix"

	# Check that we didn't break something, and get jq to canonicalize the
	# formatting. (We do literal file-comparisons when unit-testing these
	# functions, so output needs to be predictable.)
	if ! input=$(echo "$input" | jq -c 2> /dev/null); then
		echo "Error, invalid JSON" >&2
		exit 1
	fi
fi

	# input is now the output
	if [[ -n $outputfile ]]; then
		echo "$input" > $outputfile
	else
		echo "$input"
	fi
	true
}

# hjs_single_expand()
#
# This function takes a JSON-encoded set of key-value pairs, and uses them to
# filter from an input file (default stdin) to an output file (default stdout),
# performing parameter expansion based on those key-value pairs. The input and
# output is raw text from our perspective (probably JSON at higher-layers, but
# here we don't care), and the search-and-replace for the expansions is done by
# bash's "${abcxxf//xx/de}" construct for string-substitution. The only
# structured data here is the JSON input to provide the key-value pairs to
# search and replace with.
#
# The only non-trivial thing here is; the search and replace doesn't search for
# "key", but for "{key}". That's the only reason this function is called
# "parameter-expansion" rather than just "string-substitution".
#
# Eg. if the JSON key-value pairs are;
#   {
#       "name": "someserver",
#       "domain": "hcphacking.xyz",
#       "fqdn": "{name}.{domain}",
#       "healthcheck": "https://{fqdn}/healthcheck"
#   }
# Then it may take up to 3 passes of parameter expansion for "{healthcheck}" to
# resolve.
#
# Note, simplicity and security are the focus here, not performance;
#  - All input is read before any processing occurs, so don't stream terrabyes
#    through this, you'll be ... disappointed.
#  - This does not match on any/all parameter-like text, it looks explicitly
#    for the keys in the key-value pairs, or rather, it searches for the
#    '{key}' form of each 'key', one by one.
#     - If 'key' isn't in the JSON, then '{key}' remains unmodified. (This
#       helps if you want to filter multiple times with different inputs.)
#     - If one key is a substring of another key, no worries. That's why this
#       only supports the '{key}' form, rather than things ike '$key', where
#       that can be a problem.
#     - Use of "{key}" also means that input can appear as valid JSON prior to
#       expansion!
#  - This filter doesn't support any escaping. Ie. if 'key' is in the
#    JSON key-value pairs, there is no way to avoid any occurances of '{key}'
#    getting replaced.
#     - Yes, this isn't pure and won't support arbitrary input.
#     - The only pure way to avoid this kind of problem is to process the
#       entire input for escaping, but that's out of scope and undesirable in
#       any case. We want the input to match the output in every respect
#       _except_ for the substitutions that occurred. (Forcing inputs to be
#       escaped is an unhappy place to be, _especially_ if you want to allow
#       the input to be filtered multiple times...)
#     - Any less pure solution will just create other conundrums and
#       inconsistencies.
#     - If you're disappointed, go whine to Kurt Godel, it's probably his fault.
#  - Text only. If you pipe binary (or weird text encodings) through this,
#    you're on your own. Specifically;
#     - keys can only contain [A-Za-z0-9_], in regex-speak.
#     - substitutions use bash's "output=${input//$from/$to}" operator.
#     - hopefully LOCALE and so forth make this do the right thing when your
#       regionalization is significantly different to mine, but I'll gladly
#       take a patch from an i8n guru.
#
# Arguments:
#
# -i <file>
#   reads from the given file instead of stdin
# -o <file>
#   writes output to the given file instead of stdout
# -j <file>
#   reads JSON key-value pairs from the given file
# -J <string>
#   a string encoding the JSON key-value pairs
# -X <length>
#   bail out with an error if any string exceeds this length.
##### -m <num>
#####   parameter-expansion repeats no more than <num> iterations, even if the
#####   output keeps changing. (<num>=0 does nothing)

function hjs_single_expand {
	local inputfile
	local outputfile
	local json
	local jsonfile
	local input
	local maxsize
	while [[ $# -gt 0 ]]; do
		arg=$1
		shift
		if [[ $# -eq 0 ]]; then
			echo "Error, parsing failed on argument: $arg" >&2
			exit 1
		fi
		case $arg in 
		-i)
			if [[ -n $inputfile ]]; then
				echo "Error, -i specified more than once" >&2
				exit 1
			fi
			inputfile=$1
			if [[ ! -f $inputfile ]]; then
				echo "Error, input file doesn't exist: $inputfile" >&2
				exit 1
			fi
			;;
		-o)
			if [[ -n $outputfile ]]; then
				echo "Error, -o specified more than once" >&2
				exit 1
			fi
			outputfile=$1
			;;
		-j)
			if [[ -n $jsonfile || -n $json ]]; then
				echo "Error, -j/-J specified more than once" >&2
				exit 1
			fi
			jsonfile=$1
			if [[ ! -f $jsonfile ]]; then
				echo "Error, no such file: $jsonfile" >&2
				exit 1
			fi
			;;
		-J)
			if [[ -n $jsonfile || -n $json ]]; then
				echo "Error, -j/-J specified more than once" >&2
				exit 1
			fi
			json=$1
			[[ -n $json ]] || json="{}"
			;;
		-X)
			if [[ -n $maxsize ]]; then
				echo "Error, -X specified more than once" >&2
				exit 1
			fi
			maxsize=$1
			;;
		*)
			echo "Error, unrecognized argument: $arg" >&2
			exit 1
			;;
		esac
		shift
	done

	# Read the input
	[[ -n $inputfile ]] || inputfile=-
	input=$(cat "$inputfile")

	# Make sure we have json key-value pairs
	if [[ -z $json && -z $jsonfile ]]; then
		echo "Error, neither -j nor -J specified" >&2
		exit 1
	fi
	[[ -n $json ]] || json=$(cat $jsonfile)
	[[ -n $json ]] || json="{}"
	# ... and that it's valid JSON
	if ! json=$(echo "$json" | jq -c 2> /dev/null); then
		echo "Error, invalid JSON" >&2
		exit 1
	fi

	# Confirm that maxsize is valid
	[[ -n $maxsize ]] || maxsize=$((1*1024*1024))
	if ! [ "$maxsize" -eq "$maxsize" ] 2> /dev/null; then
		echo "Error, invalid 'maxsize': $maxsize" >&2
		exit 1
	fi

	keys=( $(echo "$json" | jq -r 'keys[] // empty') )
	for i in ${keys[@]}; do
		if ! hjs_valid_key "$i"; then
			echo "Error, invalid characters in JSON key: $i" >&2
			exit 1
		fi
		# NOTE: we're counting on hjs_valid_key limiting $i to
		# alphanumeric and underscore characters, and so ".$i"
		# should be a valid jq recipe without any unexpected
		# consequences.
		val=$(echo "$json" | jq -r ".$i // empty")
		# The text we need to find and replace is "{key}"
		literalkey="{$i}"
		# Let bash do the parameter-expansion
		input=${input//$literalkey/$val}
		# Check we're not exploding
		hjs_check_maxsize "$input" $maxsize
	done

	# input is now the output
	if [[ -n $outputfile ]]; then
		echo "$input" > "$outputfile"
	else
		echo "$input"
	fi
	true
}

# hjs_json_merge()
#
# This function filters an input JSON to an output JSON, from stdin to stdout
# by default (see -i and -o), and uses a JSON structure of key-value pairs to
# cause JSON objects to be imported from other files and merged in at various
# "paths" within the filtered object.
#
# The key-value pairs that trigger these "merge imports" are actually just a
# set of values. The keys must simply be unique, so typically have descriptive
# purpose. The values are strings of the form "<jsonpath>:<filepath>", where
# <jsonpath> is a dot-separated "address" within a JSON hierarchy as described
# in hjs_from_path(), and <filepath> is for loading the to-be-merged JSON
# object.
#
# Arguments:
#
# -i <file>
#   reads from the given file instead of stdin
# -o <file>
#   writes output to the given file instead of stdout
# -j <file>
#   reads JSON key-value pairs from the given file
# -J <string>
#   a string encoding the JSON key-value pairs
# -X <length>
#   bail out with an error if any string exceeds this length.

function hjs_json_merge {
	local inputfile
	local outputfile
	local json
	local jsonfile
	local input
	local maxsize
	while [[ $# -gt 0 ]]; do
		arg=$1
		shift
		if [[ $# -eq 0 ]]; then
			echo "Error, parsing failed on argument: $arg" >&2
			exit 1
		fi
		case $arg in 
		-i)
			if [[ -n $inputfile ]]; then
				echo "Error, -i specified more than once" >&2
				exit 1
			fi
			inputfile=$1
			if [[ ! -f $inputfile ]]; then
				echo "Error, input file doesn't exist: $inputfile" >&2
				exit 1
			fi
			;;
		-o)
			if [[ -n $outputfile ]]; then
				echo "Error, -o specified more than once" >&2
				exit 1
			fi
			outputfile=$1
			;;
		-j)
			if [[ -n $jsonfile || -n $json ]]; then
				echo "Error, -j/-J specified more than once" >&2
				exit 1
			fi
			jsonfile=$1
			if [[ ! -f $jsonfile ]]; then
				echo "Error, no such file: $jsonfile" >&2
				exit 1
			fi
			;;
		-J)
			if [[ -n $jsonfile || -n $json ]]; then
				echo "Error, -j/-J specified more than once" >&2
				exit 1
			fi
			json=$1
			[[ -n $json ]] || json="{}"
			;;
		-X)
			if [[ -n $maxsize ]]; then
				echo "Error, -X specified more than once" >&2
				exit 1
			fi
			maxsize=$1
			;;
		*)
			echo "Error, unrecognized argument: $arg" >&2
			exit 1
			;;
		esac
		shift
	done

	# Read the input and make sure it's JSON
	[[ -n $inputfile ]] || inputfile=-
	if ! input=$(cat "$inputfile" | jq -c 2> /dev/null); then
		echo "Error, input isn't valid JSON" >&2
		exit 1
	fi

	# Make sure we have JSON key-value pairs
	if [[ -z $json && -z $jsonfile ]]; then
		echo "Error, neither -j nor -J specified" >&2
		exit 1
	fi
	[[ -n $json ]] || json=$(cat $jsonfile)
	[[ -n $json ]] || json="{}"
	# and confirm they're valid too
	if ! json=$(echo "$json" | jq -c 2> /dev/null); then
		echo "Error, invalid JSON" >&2
		exit 1
	fi

	# Confirm that maxsize is valid
	[[ -n $maxsize ]] || maxsize=$((1*1024*1024))
	if ! [ "$maxsize" -eq "$maxsize" ] 2> /dev/null; then
		echo "Error, invalid 'maxsize': $maxsize" >&2
		exit 1
	fi

	# Iterate over the values in the key-value pairs
	values=( $(echo "$json" | jq -r 'values[] // empty') )
	for i in ${values[@]}; do
		# Value should be of the form;
		# path.for.json.import:/path/to/importedfile.json
		# hjs_from_path() does the difficult bit
		if ! echo "$i" | grep ":" > /dev/null; then
			echo "Error, no ':' in merge value: $i" >&2
			exit 1
		fi
		# Deconstruct
		jsonpath=$(echo "$i" | sed -e "s/:.*\$//")
		filepath=$(echo "$i" | sed -e "s/^.*://")
		# Import the file and convert it to a JSON at the
		# appropriate path
		tomerge=$(hjs_from_path -i "$filepath" -j "$jsonpath")
		input=$(jq -cn "$input * $tomerge")
	done

	# input is now the output
	if [[ -n $outputfile ]]; then
		echo "$input" > $outputfile
	else
		echo "$input"
	fi
	true
}


# hjs_json_expand()
#
# This function is a wrapper around hjs_single_expand() and hjs_json_merge().
# The former is used for parameter-expansion and the latter is used for
# file-inclusion.
# 
# Arguments:
#
# -i <file>
#   reads from the given file instead of stdin
# -o <file>
#   writes output to the given file instead of stdout
# -m <num>
#   parameter-expansion repeats no more than <num> iterations, even if the
#   output keeps changing. (<num>=0 does nothing)
# -X <length>
#   bail out with an error if any string exceeds this length.

function hjs_json_expand {
	local inputfile
	local outputfile
	local maxloop
	local maxsize
	local input
	local env
	while [[ $# -gt 0 ]]; do
		arg=$1
		shift
		if [[ $# -eq 0 ]]; then
			echo "Error, parsing failed on argument: $arg" >&2
			exit 1
		fi
		case $arg in
		-i)
			if [[ -n $inputfile ]]; then
				echo "Error, -i specified more than once" >&2
				exit 1
			fi
			inputfile=$1
			if [[ ! -f $inputfile ]]; then
				echo "Error, input file doesn't exist: $inputfile" >&2
				exit 1
			fi
			;;
		-o)
			if [[ -n $outputfile ]]; then
				echo "Error, -o specified more than once" >&2
				exit 1
			fi
			outputfile=$1
			;;
		-m)
			if [[ -n $maxloop ]]; then
				echo "Error, -m specified more than once" >&2
				exit 1
			fi
			maxloop=$1
			;;
		-X)
			if [[ -n $maxsize ]]; then
				echo "Error, -X specified more than once" >&2
				exit 1
			fi
			maxsize=$1
			;;
		*)
			echo "Error, unrecognized argument: $arg" >&2
			exit 1
			;;
		esac
		shift
	done

	# Read the input and confirm that it's valid JSON
	[[ -n $inputfile ]] || inputfile=-
	if ! input=$(cat "$inputfile" | jq -cS 2> /dev/null); then
		echo "Error, invalid JSON input" >&2
		exit 1
	fi

	# Confirm that maxsize is valid
	[[ -n $maxsize ]] || maxsize=$((1*1024*1024))
	if ! [ "$maxsize" -eq "$maxsize" ] 2> /dev/null ||
			[[ $maxsize -lt 1024 ]]; then
		echo "Error, invalid 'maxsize': $maxsize" >&2
		exit 1
	fi

	# Confirm that maxloop is valid
	[[ -n $maxloop ]] || maxloop=20
	if ! [ "$maxloop" -eq "$maxloop" ] 2> /dev/null ||
			[[ $maxloop -lt 1 ]]; then
		echo "Error, invalid 'maxloop': $maxloop" >&2
		exit 1
	fi

	origenv="{}"
	origfiles="{}"
	env="{}"

# Expansion and inclusion loop starts here. Negative indenting for readability.
# 'origenv' consists of all imported 'env' sections so far (and never undergoes
# any expansion). 'origfiles' is similarly all 'files' sections that have been
# absorbed, though these may be modified by 'env'-expansion.  'env' consists of
# the same key-value pairs as 'origenv', except that it is always
# fully-expanded on itself (so that it only needs to be expanded once on
# anything else!).
# The strategy from this point on;
# - loop
#   - extract and remove '__env' from input
#     - add it 'origenv'
#     - add it to 'env'
#   - fully-expand env on itself (repeat until transitive closure)
#   - use 'env' to expand once over the input
#   - extract and remove '__files' from input
#     - if __files is empty, break out of the loop
#   - add '__files' to 'origfiles'
#     - import the JSON files listed in '__files' and insert them into our
#       input at the indicated paths
#   - because __files was non-empty, input must have changed (and it may or may
#     not have brought more __env and __files content with it too). Return to
#     start of loop.
# (outside the loop)
# - add 'origenv' and 'origfiles' back to the input
# - input -> output
while : ; do

	# Extract the "env" section and remove it from $input
	newenv=$(echo "$input" | jq -r ".__env // empty")
	if [[ -z $newenv ]]; then
		newenv="{}"
	elif ! echo "$newenv" | egrep "^{" > /dev/null 2>&1; then
		# The path exists but it isn't a JSON substructure. Eg. it
		# might be a string, or an array instead.
		echo "Error, the __env field wasn't a struct" >&2
		exit 1
	else
		# Delete the env section from input
		input=$(echo "$input" | jq -cS "del(.__env)")
	fi

	# Add it to 'origenv' and use it as an opportunity to look for
	# collisions. I.e. this will catch collisions when inclusions at
	# different levels of processing try to define the same environment
	# entries, but it won't catch collisions between inclusions at the same
	# level of processing (i.e. when they're included in the same pass).
	cmporigenv=$(jq -cnS "$newenv + $origenv")
	origenv=$(jq -cnS "$origenv + $newenv")
	if [[ $cmporigenv != $origenv ]]; then
		echo "Error, collision detected in __env settings" >&2
		echo "TODO: add some jq trick in here to show" >&2
		echo "newenv + origenv: $cmporigenv" >&2
		echo "origenv + newenv: $origenv" >&2
		exit 1
	fi

	# Add it to 'env'
	env=$(jq -cnS "$env + $newenv")
	# Expand 'env' on itself until it stabilizes or we escape
	newloop=$maxloop
	while [[ $((newloop--)) -gt 0 ]]; do
		newenv=$(echo "$env" | hjs_single_expand -X $maxsize -J "$env")
		if [[ "$newenv" == "$env" ]]; then
			break;
		fi
		env=$newenv
	done

	# Expand 'env' on the input. Only need to do it once because env has
	# been fully expanded on itself (no nesting remains). Note, the "files"
	# section is still in the input at this stage, so it gets expanded.
	input=$(echo "$input" | hjs_single_expand -X $maxsize -J "$env")

	# Extract the "files" section and remove it from input
	newfiles=$(echo "$input" | jq -r ".__files // empty")
	if [[ -z $newfiles ]]; then
		newfiles="{}"
	elif ! echo "$newfiles" | egrep "^{" > /dev/null 2>&1; then
		# The path exists but it isn't a JSON substructure. Eg. it
		# might be a string, or an array instead.
		echo "Error, the __files section wasn't a struct" >&2
		exit 1
	else
		# Delete the files section from input
		input=$(echo "$input" | jq -cS "del(.__files)")
	fi


	# If it's empty JSON, break out of the loop
	if [[ $newfiles == "{}" ]]; then
		break;
	fi

	# Add it to origfiles
	origfiles=$(jq -cnS "$origfiles + $newfiles")

	# Merge files
	input=$(echo "$input" | hjs_json_merge -X $maxsize -J "$newfiles")

# Return to start of loop
done

	# Put the env and files sections back in
	toinsert=$(echo "$origenv" | hjs_from_path -j "__env")
	input=$(jq -cnS "$input * $toinsert")
	toinsert=$(echo "$origfiles" | hjs_from_path -j "__files")
	input=$(jq -cnS "$input * $toinsert")

	# input is now the output
	if [[ -n $outputfile ]]; then
		echo "$input" > "$outputfile"
	else
		echo "$input"
	fi
	true
}

# This script is usually executed to obtain the results of the
# hjs_json_expand() function. If, instead, you are including the script to
# access the APIs yourself, define HJS_DO_NOT_RUN to inhibit the following;
if [[ -z $HJS_DO_NOT_RUN ]]; then
	hjs_json_expand $@
fi
