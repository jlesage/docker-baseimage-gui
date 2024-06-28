#!/bin/sh
#
# Helper script that builds Fontconfig as a static library.
#
# A customized fontconfig library is used.  This is required to allows baseimage
# programs (like openbox and yad) to use independant fonts and font configuration
# files.  This way, these programs don't depend on distro of the baseimage.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Define software versions.
FONTCONFIG_VERSION=2.15.0

# Define software download URLs.
FONTCONFIG_URL=https://www.freedesktop.org/software/fontconfig/release/fontconfig-${FONTCONFIG_VERSION}.tar.gz

# Set same default compilation flags as abuild.
export CFLAGS="-Os -fomit-frame-pointer"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS="-Wl,--strip-all -Wl,--as-needed,-O1,--sort-common"

export CC=xx-clang
export CXX=xx-clang++

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
    pkgconfig \
    gperf \
    python3 \
    font-croscore \
"

TARGET_PKGS="\
    glib-dev \
    g++ \
    freetype-dev \
    expat-dev \
"

log "Installing required Alpine packages..."
apk --no-cache add $HOST_PKGS
xx-apk --no-cache --no-scripts add $TARGET_PKGS

#
# Install Noto fonts.
# Only the fonts used by Openbox are installed.
#
log "Installing Noto fonts..."
mkdir -p /tmp/fontconfig-install/opt/base/share/fonts
for FONT in Arimo-Regular Arimo-Bold
do
    cp -v /usr/share/fonts/croscore/$FONT.ttf /tmp/fontconfig-install/opt/base/share/fonts/
done

#
# Build fontconfig.
# The static library will be used by some baseimage programs.  We need to
# compile our own version to adjust different paths used by fontconfig.
# Note that the fontconfig cache generated by fc-cache is architecture
# dependent.  Thus, we won't generate one, but it's not a problem since
# we have very few fonts installed.
#
mkdir /tmp/fontconfig
log "Downloading fontconfig..."
curl -# -L -f ${FONTCONFIG_URL} | tar -xz --strip 1 -C /tmp/fontconfig

log "Configuring fontconfig..."
(
    cd /tmp/fontconfig && ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
        --with-default-fonts=/opt/base/share/fonts \
        --with-baseconfigdir=/opt/base/share/fontconfig \
        --with-configdir=/opt/base/share/fontconfig/conf.d \
        --with-templatedir=/opt/base/share/fontconfig/conf.avail \
        --with-cache-dir=/config/xdg/cache/fontconfig \
        --disable-shared \
        --enable-static \
        --disable-docs \
        --disable-nls \
        --disable-cache-build \
)

log "Compiling fontconfig..."
make -C /tmp/fontconfig -j$(nproc)

log "Installing fontconfig..."
make DESTDIR=/tmp/fontconfig-install -C /tmp/fontconfig install

#
# Cleanup.
#
log "Performing cleanup..."
apk --no-cache del $HOST_PKGS
xx-apk --no-cache --no-scripts del $TARGET_PKGS
apk --no-cache add util-linux # Linux tools still needed and they might be removed if pulled by dependencies.
rm -rf /tmp/fontconfig
