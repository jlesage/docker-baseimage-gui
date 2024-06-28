#!/bin/sh
#
# Helper script that builds xcompmgr as a static binary.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Define software versions.
XCOMPMGR_VERSION=1.1.9

# Use the same versions has Alpine 3.20.
LIBXDAMAGE_VERSION=1.1.6

# Define software download URLs.
XCOMPMGR_URL=https://xorg.freedesktop.org/releases/individual/app/xcompmgr-${XCOMPMGR_VERSION}.tar.xz
LIBXDAMAGE_URL=https://www.x.org/releases/individual/lib/libXdamage-${LIBXDAMAGE_VERSION}.tar.xz

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
    libxcomposite-dev \
    libxrender-dev \
    libxext-dev \
    libxext-static \
    libxcb-static \

#
# Build libXdamage.
# The static library is not provided by Alpine repository, so we need to build
# it ourself.
#
mkdir /tmp/libxdamage
log "Downloading libXdamage..."
curl -# -L -f ${LIBXDAMAGE_URL} | tar -xJ --strip 1 -C /tmp/libxdamage

log "Configuring libXdamage..."
(
    cd /tmp/libxdamage && LDFLAGS= ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
        --disable-shared \
        --enable-static \
)

log "Compiling libXdamage..."
make -C /tmp/libxdamage -j$(nproc)

log "Installing libXdamage..."
make DESTDIR=$(xx-info sysroot) -C /tmp/libxdamage install

#
# Build xcompmgr.
#
mkdir /tmp/xcompmgr
log "Downloading xcompmgr..."
curl -# -L -f ${XCOMPMGR_URL} | tar xJ --strip 1 -C /tmp/xcompmgr
log "Configuring xcompmgr..."
(
    cd /tmp/xcompmgr && \
    LIBS="-lxcb -lXdmcp -lXau" \
    ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
)
log "Compiling xcompmgr..."
make -C /tmp/xcompmgr -j$(nproc)
log "Installing xcompmgr..."
make DESTDIR=/tmp/xcompmgr-install -C /tmp/xcompmgr install
