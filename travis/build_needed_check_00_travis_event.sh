#!/bin/bash

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "${BASH_SOURCE[0]} can only be sourced."
    exit 1
fi

BUILD_NEEDED_CHECK="how the build was triggered"
BUILD_NEEDED_REASON="build triggered from $TRAVIS_EVENT_TYPE event"
BUILD_NOT_NEEDED_REASON="build triggered from a cron job"

build_needed() {
    if [ "$TRAVIS_EVENT_TYPE" == "cron" ]; then
        BUILD_NEEDED_RESULT=false
    else
        BUILD_NEEDED_RESULT=true
    fi
}
