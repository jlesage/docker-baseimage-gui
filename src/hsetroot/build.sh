#!/bin/sh
#
# Helper script that builds hsetroot as a static binary.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Set same default compilation flags as abuild.
export CFLAGS="-Os -fomit-frame-pointer -Wno-expansion-to-defined -Wall"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS="-fuse-ld=lld -Wl,--as-needed,-O1,--sort-common --static -static -Wl,--strip-all"

export CC=xx-clang
export CXX=xx-clang++

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

function log {
    echo ">>> $*"
}

#
# Install required packages.
#
HOST_PKGS="\
    curl \
    build-base \
    clang \
    lld \
    xz \
"

TARGET_PKGS="\
    g++ \
    libx11-dev \
    libx11-static \
    libxcb-static \
"

log "Installing required Alpine packages..."
apk --no-cache add $HOST_PKGS
xx-apk --no-cache --no-scripts add $TARGET_PKGS

#
# Build hsetroot.
#
log "Compiling hsetroot..."
mkdir /tmp/hsetroot
LIBS="-lX11 -lxcb -lXdmcp -lXau"
xx-clang $CFLAGS "$SCRIPT_DIR"/hsetroot.c -o /tmp/hsetroot/hsetroot $LDFLAGS $LIBS

log "Installing hsetroot..."
mkdir -p /tmp/hsetroot-install/usr/bin
cp -v /tmp/hsetroot/hsetroot /tmp/hsetroot-install/usr/bin/

#
# Cleanup.
#
log "Performing cleanup..."
apk --no-cache del $HOST_PKGS
xx-apk --no-cache --no-scripts del $TARGET_PKGS
apk --no-cache add util-linux # Linux tools still needed and they might be removed if pulled by dependencies.
rm -rf /tmp/hsetroot
