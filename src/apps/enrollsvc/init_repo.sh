#!/bin/bash

. /hcp/enrollsvc/common.sh

expect_db_user

cd $HCP_ENROLLSVC_STATE

mkdir $REPO_PATH
cd $REPO_PATH
git init
touch .git/git-daemon-export-ok
touch $HN2EK_PATH
mkdir $EK_BASENAME
touch $EK_BASENAME/do_not_remove
cp /hcp/enrollsvc/common_defs.sh .
git add .
git commit -m "Initial commit"
git log
