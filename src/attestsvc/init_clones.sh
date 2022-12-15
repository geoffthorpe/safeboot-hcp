#!/bin/bash

. /hcp/attestsvc/common.sh

expect_db_user

cd $HCP_ATTESTSVC_DB_DIR

if [[ -d A || -d B || -h current || -h next || -h thirdwheel ]]; then
	echo "Error, updater state half-baked?" >&2
	exit 1
fi

echo "First-time initialization of $HCP_ATTESTSVC_DB_DIR. Two clones and two symlinks." >&2
git clone -o origin $HCP_ATTESTSVC_REMOTE_REPO A
git clone -o twin A B
ln -s A current
ln -s B next
(cd A && git remote add twin ../B)
(cd B && git remote add origin $HCP_ATTESTSVC_REMOTE_REPO)
