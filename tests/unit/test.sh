#!/bin/bash

function abort {
	echo "Aborting: $1" >&2
	exit 1
}

# Require that we be in the top-level source directory, or that we have
# guidance
[[ -n $TEST_PATH_HCPEXPAND ]] || TEST_PATH_HCPEXPAND=/hcp/xtra/hcp_expand.sh
[[ -n $TEST_PATH_UNITS ]] || TEST_PATH_UNITS=/unit
[[ -f $TEST_PATH_HCPEXPAND ]] || abort "No hcp_expand.sh found at: $TEST_PATH_HCPEXPAND"
[[ -f $TEST_PATH_UNITS/input_basic1.json ]] || abort "No test inputs found at: $TEST_PATH_UNITS"

# Test hjs_valid_key()
function test1 {
	function item {
		hjs_valid_key "$1" && result=true || result=false
		if [[ $2 != $result ]]; then
			echo "Error, got '$result' instead of '$2'" >&2
			abort "    hjs_valid_key \"$1\""
		fi
		echo "Success: test1(hjs_valid_key):\"$2\":\"$1\""
	}
	item "" false
	item "\"\"" false
	item "{'a':'b'}" false
	item "a_012_" true
	item "___" true
	item "123455555555555555555" true
	item "123.4" false
	item "-abc" false
	item "AAAZZZZZZZZZZZZZ" true
	item "345.123" false
	item "abc.def" false
	item "a;c" false
	item "--help" false
	item "a_reasonable_key" true
}

# Test hjs_from_path()
function test2 {
	# $1 = input file
	# $2 = JSON path
	# $3 = output file (don't overwrite!)
	# $4 = true or false, expected success
	function item {
		output=$(hjs_from_path -i "$1" -j "$2") &&
			result=true || result=false
		if [[ $4 != $result ]]; then
			echo "Error, got '$result' instead of '$4'" >&2
			abort "    hjs_from_path:$1:$2:$3:$4"
		fi
		if [[ $result == true && $output != $(cat $3) ]]; then
			echo "Error, output doesn't match '$3'" >&2
			echo "$output" >&2
			abort "    hjs_from_path:$1:$2:$3:$4"
		fi
		tmpout=$(mktemp)
		cat "$1" | hjs_from_path -o "$tmpout" -j "$2" &&
			result=true || result=false
		if [[ $4 != $result ]]; then
			rm $tmpout
			echo "Error, success/failure changes across stdin/-i,stdout/-o" >&2
			echo "-i+stdout gave $4, stdin+-i gave $result" >&2
			abort "    hjs_from_path:$1:$2:$3:$4"
		fi
		if [[ $result == true && $output != $(cat $tmpout) ]]; then
			rm $tmpout
			echo "Error, output changes across stdin/-i,stdout/-o" >&2
			abort "    hjs_from_path:$1:$2:$3:$4"
		fi
		rm $tmpout
		echo "Success: test2(hjs_from_path):$1:$2:$3:$4"
	}
	item input_basic1.json "." input_basic1.json true
	item input_basic1.json "foo" input_basic2.json true
	item input_basic2.json "foo" input_basic3.json true
}

# Test hjs_single_expand()
function test3 {
	# $1 = input file (for expansion)
	# $2 = JSON file (with key-value pairs)
	# $3 = output file (don't overwrite!)
	# $4 = true or false, expected success
	function item {
		output=$(hjs_single_expand -i "$1" -j "$2") &&
			result=true || result=false
		if [[ $4 != $result ]]; then
			echo "Error, got '$result' instead of '$4'" >&2
			abort "    hjs_single_expand:$1:$2:$3:$4"
		fi
		if [[ $result == true && $output != $(cat $3) ]]; then
			echo "Error, output doesn't match '$3'" >&2
			echo "$output" >&2
			abort "    hjs_single_expand:$1:$2:$3:$4"
		fi
		tmpout=$(mktemp)
		tmpjson=$(cat "$2")
		cat "$1" | hjs_single_expand -o "$tmpout" -J "$tmpjson" &&
			result=true || result=false
		if [[ $4 != $result ]]; then
			rm $tmpout
			echo "Error, success/failure changes across stdin/-i,stdout/-o" >&2
			echo "-i+stdout gave $4, stdin+-i gave $result" >&2
			abort "    hjs_single_expand:$1:$2:$3:$4"
		fi
		if [[ $result == true && $output != $(cat $tmpout) ]]; then
			rm $tmpout
			echo "Error, output changes across stdin/-i,stdout/-o" >&2
			abort "    hjs_single_expand:$1:$2:$3:$4"
		fi
		rm $tmpout
		echo "Success: test3(hjs_single_expand):$1:$2:$3:$4"
	}
	item input_pairs1.json input_pairs1.json output_pairs1b.json true
	item output_pairs1b.json input_pairs1.json output_pairs1c.json true
	item output_pairs1c.json input_pairs1.json output_pairs1d.json true
	item output_pairs1b.json output_pairs1b.json output_pairs1d.json true
}

# Test hjs_json_merge()
function test4 {
	# $1 = input JSON file (for merging into)
	# $2 = JSON file (with key-value pairs for importing)
	# $3 = output file (don't overwrite!)
	# $4 = true or false, expected success
	function item {
		output=$(hjs_json_merge -i "$1" -j "$2") &&
			result=true || result=false
		if [[ $4 != $result ]]; then
			echo "Error, got '$result' instead of '$4'" >&2
			abort "    hjs_json_merge:$1:$2:$3:$4"
		fi
		if [[ $result == true && $output != $(cat $3) ]]; then
			echo "Error, output doesn't match '$3'" >&2
			echo "$output" >&2
			abort "    hjs_json_merge:$1:$2:$3:$4"
		fi
		tmpout=$(mktemp)
		tmpjson=$(cat "$2")
		cat "$1" | hjs_json_merge -o "$tmpout" -J "$tmpjson" &&
			result=true || result=false
		if [[ $4 != $result ]]; then
			rm $tmpout
			echo "Error, success/failure changes across stdin/-i,stdout/-o" >&2
			echo "-i+stdout gave $4, stdin+-i gave $result" >&2
			abort "    hjs_json_merge:$1:$2:$3:$4"
		fi
		if [[ $result == true && $output != $(cat $tmpout) ]]; then
			rm $tmpout
			echo "Error, output changes across stdin/-i,stdout/-o" >&2
			abort "    hjs_json_merge:$1:$2:$3:$4"
		fi
		rm $tmpout
		echo "Success: test4(hjs_json_merge):$1:$2:$3:$4"
	}
	item input_basic2.json input_merge1.json input_basic3.json true
}

# Test hjs_json_expand()
function test5 {
	# $1 = input JSON file (for merging into)
	# $2 = output file (don't overwrite!)
	# $3 = true or false, expected success
	function item {
		output=$(hjs_json_expand -i "$1") &&
			result=true || result=false
		if [[ $3 != $result ]]; then
			echo "Error, got '$result' instead of '$3'" >&2
			abort "    hjs_json_merge:$1:$2:$3"
		fi
		if [[ $result == true && $output != $(cat $2) ]]; then
			echo "Error, output doesn't match '$2'" >&2
			echo "$output" >&2
			abort "    hjs_json_merge:$1:$2:$3"
		fi
		tmpout=$(mktemp)
		cat "$1" | hjs_json_expand -o "$tmpout" &&
			result=true || result=false
		if [[ $3 != $result ]]; then
			rm $tmpout
			echo "Error, success/failure changes across stdin/-i,stdout/-o" >&2
			echo "-i+stdout gave $3, stdin+-i gave $result" >&2
			abort "    hjs_json_merge:$1:$2:$3"
		fi
		if [[ $result == true && $output != $(cat $tmpout) ]]; then
			rm $tmpout
			echo "Error, output changes across stdin/-i,stdout/-o" >&2
			abort "    hjs_json_merge:$1:$2:$3"
		fi
		rm $tmpout
		echo "Success: test5(hjs_json_expand):$1:$2:$3"
	}
	item input_full1.json output_full1.json true
}

TESTS="test1 test2 test3 test4 test5"

tmpoutput=$(mktemp)
trap 'rm $tmpoutput' EXIT

export HJS_DO_NOT_RUN=1

echo "Running unit tests"

for i in $TESTS; do
	echo "$i"
	if (source $TEST_PATH_HCPEXPAND && cd "$TEST_PATH_UNITS" && $i) > $tmpoutput 2>&1; then
		echo "Success: $i"
		cat $tmpoutput
	else
		echo "Failure: $i" >&2
		cat $tmpoutput >&2
		exit 1
	fi
done
