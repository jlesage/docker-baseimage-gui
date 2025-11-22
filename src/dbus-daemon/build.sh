#!/bin/sh
#
# Helper script that builds dbus-daemon as a static binary.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Define software versions.
# Use the same versions has Alpine 3.20.
DBUS_VERSION=1.14.10

# Define software download URLs.
DBUS_URL=https://dbus.freedesktop.org/releases/dbus/dbus-${DBUS_VERSION}.tar.xz

# Set same default compilation flags as abuild.
export CFLAGS="-Os -fomit-frame-pointer -Wno-expansion-to-defined -fno-plt"
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
    patch \
    clang \
    lld \
    pkgconfig \
"

TARGET_PKGS="\
    g++ \
    expat-dev \
    expat-static \
"

log "Installing required Alpine packages..."
apk --no-cache add $HOST_PKGS
xx-apk --no-cache --no-scripts add $TARGET_PKGS

#
# Build dbus-daemon.
#
mkdir /tmp/dbus
log "Downloading dbus-daemon..."
curl -# -L -f ${DBUS_URL} | tar xJ --strip 1 -C /tmp/dbus

log "Patching dbus-daemon..."
patch -p1 -d /tmp/dbus < "$SCRIPT_DIR"/close-all-fds.patch

log "Configuring dbus-daemon..."
(
    cd /tmp/dbus && \
    ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
        --datarootdir=/opt/base/share \
        --with-system-pid-file=/tmp/dbus-base.pid \
        --enable-debug=no \
        --enable-embedded-tests=no \
        --enable-tests=no \
        --disable-shared \
        --enable-static \
        --without-x \
)

log "Compiling dbus-daemon..."
make -C /tmp/dbus -j$(nproc)

log "Installing dbus-daemon..."
mkdir /tmp/dbus-install
make DESTDIR=/tmp/dbus-install -C /tmp/dbus install

#
# Cleanup.
#
log "Performing cleanup..."
apk --no-cache del $HOST_PKGS
xx-apk --no-cache --no-scripts del $TARGET_PKGS
apk --no-cache add util-linux # Linux tools still needed and they might be removed if pulled by dependencies.
rm -rf /tmp/dbus
