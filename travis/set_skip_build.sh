#!/bin/bash
#
# Set the TRAVIS_SKIP_BUILD variable, which indicates if the current
# build needs to be skipped or not.
#

set -e          # Exit immediately if a command exits with a non-zero status.
set -u          # Treat unset variables as an error.
set -o pipefail # Pipeline exits immediately if a command exits with a non-zero status.

PULLED_IMAGES=

cleanup() {
    EXIT_CODE=$?

    # Remove docker images we may have pulled.
    for IMG in $PULLED_IMAGES; do
        IMG_ID="$( docker image ls --format "{{.ID}}" $IMG )"
        [ -n "$IMG_ID" ] && docker rmi $IMG_ID
    done

    exit $EXIT_CODE
}
trap cleanup EXIT

# Check if we are running from a cron job.
if [ "$TRAVIS_EVENT_TYPE" == "cron" ] ; then
    echo "Running Travis CI cron job, checking if build required..."

    echo "Pulling docker image $DOCKER_REPO:$TAG..."
    docker pull $DOCKER_REPO:$TAG;
    PULLED_IMAGES="$PULLED_IMAGES $DOCKER_REPO:$TAG"

    echo "Extracting layers from docker image $DOCKER_REPO:$TAG..."
    IMAGE_LAYERS="$( docker inspect -f "{{.RootFS.Layers}}" $DOCKER_REPO:$TAG | tr -d '[]' )";

    echo "Pulling docker baseimage $BASEIMAGE..."
    docker pull $BASEIMAGE;
    PULLED_IMAGES="$PULLED_IMAGES $BASEIMAGE"

    echo "Extracting layers from docker baseimage $BASEIMAGE..."
    BASEIMAGE_LAYERS="$( docker inspect -f "{{.RootFS.Layers}}" $BASEIMAGE | tr -d '[]' )";

    if [[ "$IMAGE_LAYERS" =~ "$BASEIMAGE_LAYERS" ]]; then
        echo "Skipping cron build: Latest baseimage already in use.";
        export TRAVIS_SKIP_BUILD=1
    else
        echo "Proceeding with cron build: Baseimage update needed.";
    fi
fi

export TRAVIS_SKIP_BUILD=${TRAVIS_SKIP_BUILD:-0}
