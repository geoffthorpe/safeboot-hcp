#!/bin/bash

FILES=/etc/apt/sources.list $(ls /etc/apt/sources.list.d)

for i in $FILES; do
	sed -i "s/main/main contrib non-free/" $i
done
