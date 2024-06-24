#!/bin/sh
#
# Helper script that builds xkbcomp as a static binary.
#
# Used by the X server.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Define software versions.
# Use the same versions has Alpine 3.20.
XKBCOMP_VERSION=1.4.7

# Define software download URLs.
XKBCOMP_URL=https://www.x.org/releases/individual/app/xkbcomp-${XKBCOMP_VERSION}.tar.xz

# Set same default compilation flags as abuild.
export CFLAGS="-Os -fomit-frame-pointer -Wno-expansion-to-defined"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS="-Wl,--as-needed,-O1,--sort-common --static -static -Wl,--strip-all"

export CC=xx-clang
export CXX=xx-clang++

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

function log {
    echo ">>> $*"
}

log "Installing required Alpine packages..."
apk --no-cache add \
    curl \
    build-base \
    clang \
    pkgconfig \

xx-apk --no-cache --no-scripts add \
    g++ \
    libx11-static \
    libxcb-static \
    libxkbfile-dev \

#
# Build xkbcomp.
#
mkdir /tmp/xkbcomp
log "Downloading xkbcomp..."
curl -# -L -f ${XKBCOMP_URL} | tar xJ --strip 1 -C /tmp/xkbcomp

log "Configuring xkbcomp..."
(
    cd /tmp/xkbcomp && \
    LIBS="-lX11 -lxcb -lXdmcp -lXau" \
    ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
)

log "Compiling xkbcomp..."
make -C /tmp/xkbcomp -j$(nproc)

log "Installing xkbcomp..."
make DESTDIR=/tmp/xkbcomp-install -C /tmp/xkbcomp install
