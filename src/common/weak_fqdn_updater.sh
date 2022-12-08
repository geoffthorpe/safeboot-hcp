#!/bin/bash

source /hcp/common/hcp.sh

# This is a weakened version of fqdn_updater.py. It doesn't publish itself, so
# it simply consumes what it finds on /fqdn-bus. It's in limited bash (eg. for
# use on foreign docker images, on alpine-linux or whatever else) rather than
# python3 with lots of deps.

echo "Starting 'weak_fqdn_updater.sh'"

TFILE=$(hcp_config_extract_or ".fqdn_updater.until" "")

# We expect to be running with 1 link other than 'lo'. Find the first
# non-localhost IP address;
MYADDR=$(ip addr show | egrep "inet [0-9]" | sed -e "s/^ *inet //" | \
		sed -e "s/ .*\$//" | grep -v "127.0.0.1")

echo "MYADDR=$MYADDR"

# We need a longest-common-prefix routine to choose between the available
# addresses. Ugly, it is.
longest_common_prefix () {
  local prefix= n
  ## Truncate the two strings to the minimum of their lengths
  if [[ ${#1} -gt ${#2} ]]; then
    set -- "${1:0:${#2}}" "$2"
  else
    set -- "$1" "${2:0:${#1}}"
  fi
  ## Binary search for the first differing character, accumulating the common prefix
  while [[ ${#1} -gt 1 ]]; do
    n=$(((${#1}+1)/2))
    if [[ ${1:0:$n} == ${2:0:$n} ]]; then
      prefix=$prefix${1:0:$n}
      set -- "${1:$n}" "${2:$n}"
    else
      set -- "${1:0:$n}" "${2:0:$n}"
    fi
  done
  ## Add the one remaining character, if common
  if [[ $1 = $2 ]]; then prefix=$prefix$1; fi
  printf %s "$prefix"
}

consume_fqdn_json() {
	echo "Parsing '$1'" >&2
	parsed=$(cat "$1" | jq)
	fqdns=($(cat "$1" | jq -r ".FQDNs[]"))
	addrs=($(echo "$parsed" | jq -r ".networks[].addr"))
	echo " - addresses: ${addrs[@]}" >&2
	# We will pick the one that has the longest common prefix with our own
	# IP address.
	chosen_lcp=""
	chosen=""
	for i in ${addrs[@]}; do
		lcp=$(longest_common_prefix "$MYADDR" "$i")
		if [[ ${#lcp} -gt ${#chosen_lcp} ]]; then
			chosen_lcp=$lcp
			chosen=$i
			echo " - closest so far is: $chosen" >&2
		fi
	done
	# Feed output directly onto /etc/hosts - this can only run once
	echo "## Added from $1" >> /etc/hosts
	for i in ${fqdns[@]}; do
		echo "$chosen $i" >> /etc/hosts
	done
}

for i in /fqdn-bus/fqdn-*.json; do
	consume_fqdn_json $i
done

echo "Setting touch file: $TFILE"
touch "$TFILE"
