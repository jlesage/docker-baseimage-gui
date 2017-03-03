#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

TARGET_BRANCH=$TAG

# Switch to proper branch and sync it with master.
git branch | grep -w -q $TARGET_BRANCH || git branch $TARGET_BRANCH
git checkout $TARGET_BRANCH
git rebase master

# Generate and validate the Dockerfile.
echo "Generating and validating the Dockerfile..."
travis/before_script.sh

echo "The following change will be pushed to branch $TARGET_BRANCH:"
git diff -u Dockerfile

# Add and commit the Dockerfile.
git add Dockerfile
git commit
    -m "Automatic Dockerfile deployment from Travis CI (build $TRAVIS_BUILD_NUMBER)."
    --author="Travis CI <$COMMIT_AUTHOR_EMAIL>"

# Push the change.
echo "Pushing change to repository..."
REPO=$(git config remote.origin.url)
REPO=${REPO/https:\/\//https:\/\/$GIT_PERSONAL_ACCESS_TOKEN@}
git push $REPO $TAG
