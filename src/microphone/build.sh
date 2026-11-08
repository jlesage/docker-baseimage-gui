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
# Keep in sync with microphone.c: short-read IO and an 8192-byte internal buffer.
NESTEGG_VERSION=767aab25013acefbdcc6d68a2a7a2c9081303e3f

# Define software download URLs.
OPUS_URL=https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz
NESTEGG_URL=https://github.com/mozilla/nestegg/archive/${NESTEGG_VERSION}.tar.gz

# Set same default compilation flags as abuild.
export CFLAGS="-Os -fomit-frame-pointer -ffunction-sections -fdata-sections"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS="-Wl,--gc-sections"

export CC=xx-clang
export CXX=xx-clang++
export PKG_CONFIG="$(xx-info)-pkg-config"

# Use LLVM archive tools for target libraries alongside the Clang cross-compiler.
export AR=llvm-ar
export RANLIB=llvm-ranlib

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR=/tmp/microphone-libraries

log() {
    echo ">>> $*"
}

#
# Required packages.
# Build tools run on BUILDPLATFORM; libraries/headers target TARGETPLATFORM.
#
HOST_PKGS="\
    curl \
    clang \
    lld \
    llvm \
    make \
    pkgconf \
    autoconf \
    automake \
    libtool \
"

TARGET_PKGS="\
    gcc \
    musl-dev \
    glib-dev \
    glib-static \
    libffi-dev \
    util-linux-static \
"

#
# Build Opus.
# Alpine 3.20 ships no libopus.a, so build the target library from source.
#
build_opus() {
    mkdir -p "$BUILD_DIR/opus"
    log "Downloading Opus..."
    # Do not restore archive ownership when building under rootless Podman.
    curl -# -L -f ${OPUS_URL} | tar -xz --no-same-owner --strip 1 -C "$BUILD_DIR/opus"

    log "Configuring Opus..."
    (
        cd "$BUILD_DIR/opus" && \
        ./configure \
            --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
            --host=$(xx-clang --print-target-triple) \
            --prefix=/usr \
            --libdir=/usr/lib \
            --enable-static \
            --disable-shared \
            --disable-extra-programs \
            --disable-doc \
            --disable-asm
    )

    log "Compiling Opus..."
    make -C "$BUILD_DIR/opus" -j$(nproc)

    log "Installing Opus..."
    DESTDIR=$(xx-info sysroot) make -C "$BUILD_DIR/opus" install
}

#
# Build nestegg.
# Use a pinned revision with the short-read IO callback API.
#
build_nestegg() {
    mkdir -p "$BUILD_DIR/nestegg"
    log "Downloading nestegg..."
    curl -# -L -f ${NESTEGG_URL} | tar -xz --no-same-owner --strip 1 -C "$BUILD_DIR/nestegg"

    log "Configuring nestegg..."
    (
        cd "$BUILD_DIR/nestegg" && \
        autoreconf -ivf && \
        ./configure \
            --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
            --host=$(xx-clang --print-target-triple) \
            --prefix=/usr \
            --libdir=/usr/lib \
            --enable-static \
            --disable-shared \
            --disable-doc
    )

    log "Compiling nestegg..."
    make -C "$BUILD_DIR/nestegg" -j$(nproc)

    log "Installing nestegg..."
    DESTDIR=$(xx-info sysroot) make -C "$BUILD_DIR/nestegg" install
}

# Keep dependency compilation in its own image layer for source-only rebuilds.
build_libraries() {
    log "Installing required Alpine packages..."
    apk --no-cache add $HOST_PKGS
    xx-apk --no-cache --no-scripts add $TARGET_PKGS

    build_opus
    build_nestegg

    log "Performing cleanup..."
    rm -rf "$BUILD_DIR"
    # Keep the toolchain and development libraries for the binary build layer.
}

#
# Build the microphone bridge.
#
build_microphone() {
    log "Compiling microphone..."
    make -C "$SCRIPT_DIR" -j$(nproc)
}

case "${1:-all}" in
    libraries)
        build_libraries
        ;;
    binary)
        build_microphone
        ;;
    all)
        build_libraries
        build_microphone
        ;;
    *)
        echo "Usage: $0 [libraries|binary|all]" >&2
        exit 1
        ;;
esac
