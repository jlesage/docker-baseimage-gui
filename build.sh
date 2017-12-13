#!/bin/bash

set -e

SCRIPT_DIR="$(readlink -f "$(dirname "$0")")"

usage() {
    if [ "$*" ]; then
        echo "$*"
        echo
    fi

    echo "usage: $( basename $0 ) [OPTION]... DOCKER_TAG [DOCKER_TAG]...

Arguments:
  DOCKER_TAG          Defines the container flavor to build.  Valid values are:
$(find "$SCRIPT_DIR"/versions -type f -printf '                        %f\n' | sort)
                        all
Options:
  -c, --without-cache Do not use the Docker cache when building.
  -h, --help          Display this help.
"
}

requirements() {
    if [ -z "$( which bats )" ]; then
        echo "ERROR: To run test, bats needs to be installed."
    fi
}

# Parse arguments.
while [[ $# > 0 ]]
do
    key="$1"

    case $key in
        -c|--without-cache)
            USE_DOCKER_BUILD_CACHE=0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            usage "ERROR: Unknown argument: $key"
            exit 1
            ;;
        *)
            break
            ;;
    esac
    shift
done

DOCKER_TAGS="$*"

[ -z "$DOCKER_TAGS" ] && usage "ERROR: At least one Docker tag must be specified." && exit 1
[ "$DOCKER_TAGS" == "all" ] && DOCKER_TAGS="$(find "$SCRIPT_DIR"/versions -type f -printf '%f ' | sort)"
for DOCKER_TAG in $DOCKER_TAGS; do
    if [ ! -f "$SCRIPT_DIR"/versions/"$DOCKER_TAG" ]; then
        usage "ERROR: Invalid docker tag: $DOCKER_TAG."
        exit 1
    fi
done

for DOCKER_TAG in $DOCKER_TAGS; do
    # Export build variables.
    export DOCKER_REPO=jlesage/baseimage-gui
    export DOCKER_TAG=$DOCKER_TAG
    export USE_DOCKER_BUILD_CACHE=${USE_DOCKER_BUILD_CACHE:-1}

    # Build.
    hooks/pre_build
    hooks/build

    # Run tests.
    for i in $(seq -s ' ' 1 5 | rev)
    do
        echo "Starting tests of Docker image $DOCKER_REPO:$DOCKER_TAG in $i..."
        sleep 1
    done
    env DOCKER_IMAGE="$DOCKER_REPO:$DOCKER_TAG" bats tests
done
