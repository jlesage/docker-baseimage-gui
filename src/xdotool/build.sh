#!/bin/sh
#
# Helper script that builds xdotool as a static binary.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Define software versions.
XDOTOOL_VERSION=4.20251130.1

# Define software download URLs.
XDOTOOL_URL=https://github.com/jordansissel/xdotool/releases/download/v${XDOTOOL_VERSION}/xdotool-${XDOTOOL_VERSION}.tar.gz

# Set same default compilation flags as abuild.
export CFLAGS="-Os -fomit-frame-pointer -Wno-expansion-to-defined"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS="-fuse-ld=lld -Wl,--as-needed,-O1,--sort-common --static -static -Wl,--strip-all"

export CC=xx-clang
export CXX=xx-clang++

export PREFIX=/usr

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
    patch \
    clang \
    lld \
    pkgconf \
"

TARGET_PKGS="\
    g++ \
    libx11-dev \
    libx11-static \
    libxtst-dev \
    libxtst-static \
    libxinerama-dev \
    libxkbcommon-dev \
    libxkbcommon-static \
    libxcb-static \
    libxext-static \
"

log "Installing required Alpine packages..."
apk --no-cache add $HOST_PKGS
xx-apk --no-cache --no-scripts add $TARGET_PKGS

#
# Build xdotool.
#
mkdir /tmp/xdotool
log "Downloading xdotool..."
curl -# -L -f ${XDOTOOL_URL} | tar xz --strip 1 -C /tmp/xdotool

log "Patching xdotool..."
patch -p1 -d /tmp/xdotool < "$SCRIPT_DIR"/makefile.patch

log "Compiling xdotool..."
make -C /tmp/xdotool -j$(nproc) static

log "Installing xdotool..."
make DESTDIR=/tmp/xdotool-install -C /tmp/xdotool install-static

#
# Cleanup.
#
log "Performing cleanup..."
apk --no-cache del $HOST_PKGS
xx-apk --no-cache --no-scripts del $TARGET_PKGS
apk --no-cache add util-linux # Linux tools still needed and they might be removed if pulled by dependencies.
rm -rf /tmp/xdotool
