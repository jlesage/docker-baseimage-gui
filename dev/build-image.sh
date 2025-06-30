#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(realpath "${SCRIPT_DIR}"/../)"

IMAGE=jlesage/baseimage-gui:dev
BASEIMAGE=jlesage/baseimage:alpine-3.21-v3.7.1
PLATFORM=linux/amd64
RUN_UNIT_TESTS=false

usage() {
    if [ -n "${1:-}" ]; then
        >&2 echo "$@"
        >&2 echo ""
    fi
    >&2 echo "usage: $0 [OPTION...]

Options:
    --imagename       Name of the image to produce (default: ${IMAGE}).
    --baseimage       Baseimage to use (default: ${BASEIMAGE}).
    --platform        Platform to build (default: ${PLATFORM}).
    --run-unit-tests  Run unit tests after building the image.
    --help, -h        Print this help.
"
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --help | -h)
            usage
            ;;
        --imagename)
            shift
            [ -n "${1:-}" ] || usage "Name of the image not specified."
            IMAGE="$1"
            ;;
        --baseimage)
            shift
            [ -n "${1:-}" ] || usage "Baseimage not specified."
            BASEIMAGE="$1"
            ;;
        --platform)
            shift
            [ -n "${1:-}" ] || usage "Platform not specified."
            PLATFORM="$1"
            ;;
        --run-unit-tests)
            RUN_UNIT_TESTS=true
            ;;
        --*)
            usage "Unknown option: $1"
            ;;
        *)
            usage "Unknown argument: $1"
            ;;
    esac
    shift
done

# Build the common software included in the base image.
docker buildx build \
    --progress plain \
    --load \
    --platform "${PLATFORM}" \
    -f "${BASE_DIR}"/Dockerfile.common \
    -t "${IMAGE}-common" \
    "${BASE_DIR}"

# Build the base image.
docker buildx build \
    --progress plain \
    --load \
    --platform "${PLATFORM}" \
    --build-arg BASEIMAGE_COMMON="${IMAGE}-common" \
    --build-arg BASEIMAGE="${BASEIMAGE}" \
    -f "${BASE_DIR}"/Dockerfile \
    -t "${IMAGE}" \
    "${BASE_DIR}"

echo "Docker image ${IMAGE} built successfully."

if ${RUN_UNIT_TESTS}; then
    echo "Running unit tests on ${IMAGE}..."
    DOCKER_IMAGE="${IMAGE}" bats -j "$(nproc)" "${BASE_DIR}"/tests
fi

# vim:ft=sh:ts=4:sw=4:et:sts=4
