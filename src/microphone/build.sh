#!/bin/sh
#
# Helper script that builds the microphone bridge as a static binary.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Define software versions.
OPUS_VERSION=1.5.2
NESTEGG_COMMIT=767aab25013acefbdcc6d68a2a7a2c9081303e3f

# Define software download URLs.
OPUS_URL=https://github.com/xiph/opus/releases/download/v${OPUS_VERSION}/opus-${OPUS_VERSION}.tar.gz
NESTEGG_URL=https://github.com/mozilla/nestegg/archive/${NESTEGG_COMMIT}.tar.gz

# Set same default compilation flags as abuild.
export CFLAGS="-Os -fomit-frame-pointer -fPIC -ffunction-sections -fdata-sections"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS="-Wl,--gc-sections"

export CC=xx-clang
export CXX=xx-clang++

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log() {
    echo ">>> $*"
}

#
# Install required packages.
#
HOST_PKGS="\
    curl \
    build-base \
    clang \
    pkgconfig \
"

TARGET_PKGS="\
    g++ \
"

log "Installing required Alpine packages..."
apk --no-cache add $HOST_PKGS
xx-apk --no-cache --no-scripts add $TARGET_PKGS

#
# Build Opus.
#
mkdir /tmp/opus
log "Downloading Opus..."
curl -# -L -f ${OPUS_URL} | tar -xz --strip 1 -C /tmp/opus

# Assembly is disabled so every target architecture builds the same portable decoder.
log "Configuring Opus..."
(
    cd /tmp/opus && ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
        --enable-static \
        --disable-shared \
        --disable-doc \
        --disable-extra-programs \
        --disable-asm \
        --disable-rtcd \
        --disable-intrinsics
)

log "Compiling Opus..."
make -C /tmp/opus -j$(nproc)

log "Installing Opus..."
DESTDIR=$(xx-info sysroot) make -C /tmp/opus install

#
# Download nestegg. It is compiled with the bridge.
#
mkdir /tmp/nestegg
log "Downloading nestegg..."
curl -# -L -f ${NESTEGG_URL} | tar -xz --strip 1 -C /tmp/nestegg

#
# Build the microphone bridge.
#
log "Compiling microphone bridge..."
make -C "$SCRIPT_DIR" -j$(nproc) \
    NESTEGG_SRC=/tmp/nestegg/src/nestegg.c \
    NESTEGG_INC=/tmp/nestegg/include

#
# Cleanup.
#
log "Performing cleanup..."
apk --no-cache del $HOST_PKGS
xx-apk --no-cache --no-scripts del $TARGET_PKGS
apk --no-cache add util-linux # Linux tools still needed and they might be removed if pulled by dependencies.
rm -rf /tmp/opus /tmp/nestegg
