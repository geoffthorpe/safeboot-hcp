#!/bin/bash

. /hcp/attestsvc/common.sh

expect_hcp_user

cd $HCP_USER_DIR

if [[ -d A || -d B || -h current || -h next || -h thirdwheel ]]; then
	echo "Error, updater state half-baked?" >&2
	exit 1
fi

echo "First-time initialization of $HCP_USER_DIR. Two clones and two symlinks." >&2
waitcount=0
until git clone -o origin $HCP_ATTESTSVC_REMOTE_REPO A; do
	waitcount=$((waitcount+1))
	if [[ $waitcount -eq 1 ]]; then
		echo "Warning: attestsvc 'init_clones' can't clone from enrollsvc, waiting" >&2
	fi
	if [[ $waitcount -eq 11 ]]; then
		echo "Warning: attestsvc 'init_clones' waited for another 10 seconds" >&2
		waitcount=1
	fi
	sleep 1
done
git clone -o twin A B
ln -s A current
ln -s B next
(cd A && git remote add twin ../B)
(cd B && git remote add origin $HCP_ATTESTSVC_REMOTE_REPO)
