#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

if [ "$USE_DOCKER_BUILD_CACHE" -eq 1 ]; then
    DOCKER_BUILD_CACHE_OPTS=
else
    DOCKER_BUILD_CACHE_OPTS="--no-cache --pull"
fi

echo "Starting build of Docker image $DOCKER_REPO:$TRAVIS_JOB_ID..."
docker build $DOCKER_BUILD_CACHE_OPTS \
             --build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
             -t $DOCKER_REPO:$TRAVIS_JOB_ID .
docker tag $DOCKER_REPO:$TRAVIS_JOB_ID $DOCKER_REPO:$TAG

echo "Starting tests of Docker image $DOCKER_REPO:$TRAVIS_JOB_ID..."
bats travis/tests
