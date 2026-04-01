#!/bin/sh
#
# Helper script that builds fastcompmgr as a static binary.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Define software versions.
FASTCOMPMGR_VERSION=0.6.1

# Use the same versions has Alpine 3.20.
LIBXDAMAGE_VERSION=1.1.6

# Define software download URLs.
FASTCOMPMGR_URL=https://github.com/tycho-kirchner/fastcompmgr/archive/refs/tags/v${FASTCOMPMGR_VERSION}.tar.gz
LIBXDAMAGE_URL=https://www.x.org/releases/individual/lib/libXdamage-${LIBXDAMAGE_VERSION}.tar.xz

# Set same default compilation flags as abuild.
export CFLAGS="-Os -fomit-frame-pointer -Wno-expansion-to-defined"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS="-fuse-ld=lld -Wl,--as-needed,-O1,--sort-common --static -static -Wl,--strip-all"

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
    lld \
    patch \
    pkgconfig \
"

TARGET_PKGS="\
    g++ \
    libx11-static \
    libxcomposite-dev \
    libxrender-dev \
    libxext-dev \
    libxext-static \
    libxcb-static \
"

log "Installing required Alpine packages..."
apk --no-cache add $HOST_PKGS
xx-apk --no-cache --no-scripts add $TARGET_PKGS

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
# Build fastcompmgr.
#
mkdir /tmp/fastcompmgr
log "Downloading fastcompmgr..."
curl -# -L -f ${FASTCOMPMGR_URL} | tar xz --strip 1 -C /tmp/fastcompmgr
log "Patching fastcompmgr..."
patch -p1 -d /tmp/fastcompmgr < "$SCRIPT_DIR"/fix-compile.patch
log "Compiling fastcompmgr..."
make PKGCONFIG=$(xx-info)-pkg-config -C /tmp/fastcompmgr -j$(nproc)
log "Installing fastcompmgr..."
make PREFIX=/tmp/fastcompmgr-install/usr -C /tmp/fastcompmgr install

#
# Cleanup.
#
log "Performing cleanup..."
apk --no-cache del $HOST_PKGS
xx-apk --no-cache --no-scripts del $TARGET_PKGS
apk --no-cache add util-linux # Linux tools still needed and they might be removed if pulled by dependencies.
rm -rf /tmp/fastcompmgr
