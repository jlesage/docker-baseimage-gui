#!/bin/sh
#
# Helper script that builds the intel_clc compiler.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Define software versions.
# Version used to build TigerVNC should match.
MESA_VERSION=24.2.8
LLVM_VERSION=19.1.4

# Define software download URLs.
MESA_URL=https://archive.mesa3d.org/mesa-${MESA_VERSION}.tar.xz

# Set same default compilation flags as abuild.
export CFLAGS="-Os -fomit-frame-pointer -fno-plt"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS="-fuse-ld=mold -Wl,--as-needed,-O1,--sort-common -Wl,--strip-all"

export CC=clang
export CXX=clang++

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log() {
    echo ">>> $*"
}

case "$(xx-info march)" in
    amd64|x86_64)
        ;;
    386|i386)
        ;;
    *)
        echo "Intel CLC compiler not needed for $(xx-info march)."
        mkdir /tmp/intel_clc_install
        exit 0
esac

#
# Install required packages.
#
HOST_PKGS="\
    bash \
    curl \
    xz \
    build-base \
    abuild \
    clang \
    mold \
    meson \
    pkgconf \
    py3-mako \
    py3-yaml \
    py3-setuptools \
    \
    libxml2-dev \
    llvm${LLVM_VERSION%%\.*}-static \
    clang${LLVM_VERSION%%\.*}-dev \
    clang${LLVM_VERSION%%\.*}-static \
    libclc-dev \
    spirv-tools-dev \
    spirv-llvm-translator-dev \
"

log "Installing required Alpine packages..."
apk --no-cache add $HOST_PKGS

#
# Build the Intel CLC compiler, provided by Mesa.
#
mkdir /tmp/mesa
log "Downloading mesa..."
curl -# -L -f ${MESA_URL} | tar -xJ --strip 1 -C /tmp/mesa

log "Configuring mesa..."
(
    cd /tmp/mesa && abuild-meson \
        -Db_ndebug=true \
        -Dllvm=enabled \
        -Dshared-llvm=disabled \
        -Dintel-clc=enabled \
        -Dgallium-drivers='' \
        -Dvulkan-drivers='' \
        -Dplatforms='' \
        -Dglx=disabled \
        -Dlibunwind=disabled \
        -Dzstd=disabled \
        . build
    meson configure --no-pager /tmp/mesa/build
)

log "Compiling mesa..."
meson compile -C /tmp/mesa/build
log "Installing mesa..."
mkdir -p /tmp/intel_clc_install/usr/bin
cp -av /tmp/mesa/build/src/intel/compiler/intel_clc /tmp/intel_clc_install/usr/bin/

#
#
# Cleanup.
#
log "Performing cleanup..."
apk --no-cache del $HOST_PKGS
apk --no-cache add util-linux # Linux tools still needed and they might be removed if pulled by dependencies.
rm -rf /tmp/mesa
