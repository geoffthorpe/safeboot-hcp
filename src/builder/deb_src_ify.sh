#!/bin/bash

FILES="/etc/apt/sources.list $(ls /etc/apt/sources.list.d)"

for i in $FILES; do
	cat $i | (
		while read firstword remainder; do
			echo "$firstword $remainder"
			if [[ $firstword == "deb" ]]; then
				if ! egrep "^deb-src $remainder" $i; then
					echo "deb-src $remainder"
				fi
			fi
		done
	) > $i.new
	mv $i.new $i
done
