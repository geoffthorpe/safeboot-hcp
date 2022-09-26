#!/bin/bash

source /hcp/enrollsvc/common.sh

expect_db_user

# The web framework is running as "flask_user" and it has a single sudo rule
# allowing it to run this script (and no other) as "db_user". The first
# parameter of the call must match one of the operations we define here ("add",
# "query", ...). If this matches, we also check that the number of arguments
# provided is an exact match with what we expect/allow. At that point, we will
# pass control the corresponding python script (along with the remaining
# arguments). NB, it is the responsibility of each python script to _validate_
# the arguments.
if [[ $# -lt 1 ]]; then
	echo "ERROR: insufficient arguments to mgmt_sudo.sh" >&2
	exit 1
fi

cmd=$1
shift

# $1 = num args given
# $2 = num args expected
function check_arg_num {
	if [[ $1 -ne $2 ]]; then
		echo "ERROR: '$cmd' argument-count must be $2, not $1" >&2
		exit 1
	fi
}

case $cmd in

	add)
		check_arg_num $# 3
		exec python3 /hcp/enrollsvc/db_add.py add "$1" "$2" "$3"
		;;

	query | delete)
		check_arg_num $# 1
		if [[ $cmd == "delete" ]]; then
			export QUERY_PLEASE_ALSO_DELETE=1
		fi
		exec python3 /hcp/enrollsvc/db_query.py "$1"
		;;

	reenroll)
		check_arg_num $# 1
		exec python3 /hcp/enrollsvc/db_add.py reenroll "$1"
		;;

	find)
		check_arg_num $# 1
		exec python3 /hcp/enrollsvc/db_find.py "$1"
		;;

	janitor)
		check_arg_num $# 0
		exec python3 /hcp/enrollsvc/db_janitor.py
		;;

	*)
		echo "ERROR: unrecognized command!" >&2
		exit 1
		;;
esac
