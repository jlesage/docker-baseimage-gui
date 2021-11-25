#!/bin/sh
#
# Helper script that builds xprop as a static binary.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Define software versions.
XPROP_VERSION=1.2.5

# Define software download URLs.
XPROP_URL=https://www.x.org/archive/individual/app/xprop-${XPROP_VERSION}.tar.bz2

# Set same default compilation flags as abuild.
export CFLAGS="-Os -fomit-frame-pointer"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS="-Wl,--as-needed --static -static -Wl,--strip-all -Wl,--start-group -lX11 -lxcb -lXdmcp -lXau -Wl,--end-group"

export CC=xx-clang

function log {
    echo ">>> $*"
}

#
# Install required packages.
#
log "Installing required Alpine packages..."
apk --no-cache add \
    curl \
    build-base \
    clang \
    pkgconfig \

xx-apk --no-cache --no-scripts add \
    gcc \
    musl-dev \
    glib-dev \
    libx11-dev \
    libx11-static \
    libxcb-static \
    libxdmcp-dev \
    libxau-dev \

#
# Build xprop.
#
mkdir /tmp/xprop
log "Downloading xprop..."
curl -# -L ${XPROP_URL} | tar -xj --strip 1 -C /tmp/xprop

log "Configuring xprop..."
(
    cd /tmp/xprop && LIBS="$LDFLAGS" ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
)

log "Compiling xprop..."
make -C /tmp/xprop -j$(nproc)

log "Installing xprop..."
make DESTDIR=/tmp/xprop-install -C /tmp/xprop install
