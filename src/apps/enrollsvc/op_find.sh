#!/bin/bash

. /hcp/enrollsvc/common.sh

expect_db_user

echo "Starting $0" >&2
echo "  - Param1=$1 (hostname_suffix)" >&2

# Make sure the client's request is valid JSON
if ! request_json=$(echo "$1" | jq -c) > /dev/null 2>&1; then
	my_tee "Error, request is not valid JSON"
	exit 1
fi
export HCP_REQUEST_JSON="$request_json"
hostname_suffix=$(echo "$HCP_REQUEST_JSON" | jq -r '.params.hostname_suffix // empty')

check_hostname_suffix "$hostname_suffix"

cd $REPO_PATH

# The JSON output should look like;
#    {
#        "hostname_suffix": ".dmz.mydomain.foo",
#        "ekpubhashes": [
#            "abbaf00ddeadbeef"
#            ,
#            "abcdef0123456789"
#            ,
#            "ffeeddccbbaa9988"
#        ]
#    }

echo "{"
echo "  \"hostname_suffix\": \"$hostname_suffix\","
echo "  \"ekpubhashes\": ["

# The table is indexed by _reversed_ hostname, so that our hostname_suffix
# search becomes a prefix search on the table.
revsuffix=`echo "$hostname_suffix" | rev`

# The reverse lookup table file is replaced atomically by the add/delete logic,
# so when we pipe it into our filter loop below, it will remain unmodified
# throughout the loop, even if the underlying file has been unlinked from the
# file system and replaced. I.e. we don't need to copy nor lock.

# TODO: we should use 'jq' to produce the JSON, not 'echo'.

# Filter the lookup table, line by line, through a prefix comparison
(while IFS=" " read -r revhn ekpubhash
do
	if [[ $revhn == $revsuffix* ]]; then
		[[ -n $NEEDCOMMA ]] && echo "    ,"
		echo "    \"$ekpubhash\""
		NEEDCOMMA=1
	fi
done < $HN2EK_PATH) ||
	(echo "Error, the filter loop failed" >&2 && exit 1) || exit 1

echo "  ]"
echo "}"
