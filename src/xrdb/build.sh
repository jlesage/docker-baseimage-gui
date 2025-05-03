#!/bin/sh
#
# Helper script that builds xrdb as a static binary.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Define software versions.
# Use the same versions has Alpine 3.20.
XRDB_VERSION=1.2.2

# Define software download URLs.
XRDB_URL=https://www.x.org/releases/individual/app/xrdb-${XRDB_VERSION}.tar.xz

# Set same default compilation flags as abuild.
export CFLAGS="-Os -fomit-frame-pointer -Wno-expansion-to-defined"
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
    pkgconfig \
"

TARGET_PKGS="\
    g++ \
    libx11-static \
    libxcb-static \
    libxmu-dev \
"

#    libxkbfile-dev \

log "Installing required Alpine packages..."
apk --no-cache add $HOST_PKGS
xx-apk --no-cache --no-scripts add $TARGET_PKGS

#
# Build xrdb.
#
mkdir /tmp/xrdb
log "Downloading xrdb..."
curl -# -L -f ${XRDB_URL} | tar xJ --strip 1 -C /tmp/xrdb

#    LIBS="-lX11 -lxcb -lXdmcp -lXau" \

log "Configuring xrdb..."
(
    cd /tmp/xrdb && \
    LIBS="-lX11 -lxcb -lXdmcp -lXau" \
    ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
)

log "Compiling xrdb..."
make -C /tmp/xrdb -j$(nproc)

log "Installing xrdb..."
make DESTDIR=/tmp/xrdb-install -C /tmp/xrdb install

#
# Cleanup.
#
log "Performing cleanup..."
apk --no-cache del $HOST_PKGS
xx-apk --no-cache --no-scripts del $TARGET_PKGS
apk --no-cache add util-linux # Linux tools still needed and they might be removed if pulled by dependencies.
rm -rf /tmp/xrdb
