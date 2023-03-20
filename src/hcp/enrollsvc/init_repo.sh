#!/bin/bash

source /hcp/enrollsvc/common.sh

expect_db_user

# Updates to the enrollment database take the form of git commits, which must
# have a user name and email address. The following suffices in general, but
# modify it to your heart's content; it is of no immediate consequence to
# anything else in the HCP architecture. (That said, you may have or want
# higher-layer interpretations, from an operational perspective. E.g. if the
# distinct repos from multiple regions/sites are being mirrored and inspected
# for more than backup/restore purposes, perhaps the identity in the commits
# is used to disambiguate them?)
git config --global user.email 'do-not-reply@nowhere.special'
git config --global user.name 'Host Cryptographic Provisioning (HCP)'

# Now create the git repo
cd $HCP_DB_DIR
mkdir $REPO_PATH
cd $REPO_PATH
git init
touch .git/git-daemon-export-ok
echo "[]" > $HN2EK_PATH
mkdir $EK_BASENAME
touch $EK_BASENAME/do_not_remove
git add .
git commit -m "Initial commit"
git log
