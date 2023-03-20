#!/bin/bash

set -e

# check that TRUST_OUT and TRUST_IN are valid dirs and absolute
if [[ -z $TRUST_OUT || ! -d $TRUST_OUT ]]; then
	echo "Error, TRUST_OUT ($TRUST_OUT) must be a directory" >&2
	exit 1
fi
TRUST_OUT=$(cd $TRUST_OUT && pwd)
if [[ -z $TRUST_IN || ! -d $TRUST_IN ]]; then
	echo "Error, TRUST_IN ($TRUST_IN) must be a directory" >&2
	exit 1
fi
TRUST_IN=$(cd $TRUST_IN && pwd)

# Inner loop function. Checks that the source exists, is a valid DER cert,
# converts it to a PEM file in $TRUST_OUT using a hash-based name.
# $1 = Vendor name (should also be name of the current dir)
# $2 = Relative path (eg. "RootCA/foo.der")
function do_DER_file {
	if [[ ! -f $2 ]]; then
		echo "Error, $1, \"$2\" isn't a file" >&2
		exit 1
	fi
	if ! openssl x509 -inform DER -in "$2" -noout 2> /dev/null; then
		echo "Error, $1, \"$2\" isn't a DER cert" >&2
		exit 1
	fi
	local hash=$(openssl sha256 -r "$2" | cut -c1-16)
	local output_file="$TRUST_OUT/$1_$hash.pem"
	openssl x509 -inform DER -in "$2" -outform PEM -out "$output_file"
	echo "$1: $hash ($2)"
}

# For now, make the uncomfortable assumption that the vendor directories are
# named in such a way that we can form bash function names using them. Note,
# the bash function for each vendor is run from within that directory.
VENDOR_DIRS="Nuvoton"

function do_Nuvoton {
	# There should only be a RootCA directory
	testlist=$(ls)
	if [[ "RootCA" != "$testlist" ]]; then
		echo "Error, do_Nuvoton assumptions are out of date" >&2
		exit 1
	fi
	# Every file in RootCA should be a valid DER-encoded cert
	cd RootCA
	ls -1 | while read nextentry; do
		do_DER_file "Nuvoton" "$nextentry"
	done
}

cd $TRUST_IN
echo "Importing vendor certs"
for i in $VENDOR_DIRS; do
	if [[ ! -d $i ]]; then
		echo "Skipping $i, it's not present"
		continue
	fi
	echo "Processing $i"
	fn="do_$i"
	(cd $i && $fn)
done

echo "Running openssl rehash"
openssl rehash "$TRUST_OUT"
