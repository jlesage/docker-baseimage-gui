#!/bin/bash

set -e          # Exit immediately if a command exits with a non-zero status.
set -u          # Treat unset variables as an error.
set -o pipefail # Pipeline exits immediately if a command exits with a non-zero status.

CHECKS="$( find travis -type f -name 'build_needed_check_*.sh' | sort )"

BUILD_NEEDED=0

for CHECK in $CHECKS; do
    source $CHECK

    unset BUILD_NEEDED_RESULT

    echo "Deciding if build is needed: checking $BUILD_NEEDED_CHECK..."
    build_needed

    if $BUILD_NEEDED_RESULT; then
        echo "Build needed: $BUILD_NEEDED_REASON.  Skipping other checks..."
        BUILD_NEEDED=1
        break
    else
        echo "Build not needed: $BUILD_NOT_NEEDED_REASON.  Proceeding with next check..."
    fi
done

echo "export BUILD_NEEDED=$BUILD_NEEDED" >> travis/env
if [ "$BUILD_NEEDED" -eq 1 ]; then
    echo "Build will be performed."
    echo "export BUILD_NEEDED_REASON=$BUILD_NEEDED_REASON" >> travis/env
else
    echo "Build will be skipped."
fi
