#!/bin/bash
#
# Set the SKIP_BUILD variable, which indicates if the current build needs to be
# skipped or not.
#

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "${BASH_SOURCE[0]} can only be sourced."
    exit 1
fi

BUILD_NEEDED_CHECK="if a baseimage update is available"
BUILD_NEEDED_REASON="baseimage update available"
BUILD_NOT_NEEDED_REASON="latest baseimage already in use"

build_needed() {
    echo "Extracting layers from docker image $DOCKER_REPO:$TAG..."
    docker pull $DOCKER_REPO:$TAG
    IMAGE_LAYERS="$( docker inspect -f "{{.RootFS.Layers}}" $DOCKER_REPO:$TAG | tr -d '[]' )"
    docker rmi $DOCKER_REPO:$TAG

    echo "Extracting layers from docker baseimage $BASEIMAGE..."
    docker pull $BASEIMAGE
    BASEIMAGE_LAYERS="$( docker inspect -f "{{.RootFS.Layers}}" $BASEIMAGE | tr -d '[]' )"
    docker rmi $BASEIMAGE

    if [[ "$IMAGE_LAYERS" =~ "$BASEIMAGE_LAYERS" ]]; then
        return false
        echo "Build not needed: Latest baseimage already in use."
    else
        return true
        echo "Build needed: Baseimage update needed."
    fi
}
