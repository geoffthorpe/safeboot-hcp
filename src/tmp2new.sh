#!/bin/bash

# We get given a path as an argument, let's called it $path.
path=$1

# Here's what we do. We expect a file to exist at $path.tmp,
# that is intended to be moved to $path. If there is no file
# at $path, we move the file and we're done. Otherwise, we
# only replace the file if $path.tmp is different. If they
# are the same, we remove $path.tmp
if [[ ! -f "$path.tmp" ]]; then
	exit 1
fi
if [[ ! -f $path ]]; then
	mv "$path.tmp" "$path"
else
	if cmp "$path.tmp" "$path"; then
		rm "$path.tmp"
	else
		mv -f "$path.tmp" "$path"
	fi
fi
