#!/bin/sh
#
# Helper script that builds the X keyboard configuration files along with the
# compiler as a static binary.
#
# These are meant to be used by Xvnc.  By using its own instance/version of
# XKeyboard, we prevent version mismatch issues thay could occur by using
# packages from the distro of the baseimage.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Define software versions.

# If the XKeyboardConfig version is too recent compared to xorgproto/libX11,
# xkbcomp will complain with warnings like "Could not resolve keysym ...".  With
# Alpine 3.15, XKeyboardConfig version 2.32 is the latest version that doesn't produces these warnings.
XKEYBOARDCONFIG_VERSION=2.32
XKBCOMP_VERSION=1.4.5

# Define software download URLs.
XKEYBOARDCONFIG_URL=https://www.x.org/archive/individual/data/xkeyboard-config/xkeyboard-config-${XKEYBOARDCONFIG_VERSION}.tar.bz2
XKBCOMP_URL=https://www.x.org/releases/individual/app/xkbcomp-${XKBCOMP_VERSION}.tar.bz2

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
    meson \
    perl \
    util-macros \
    libxslt \

xx-apk --no-cache --no-scripts add \
    gcc \
    musl-dev \
    glib-dev \
    libx11-dev \
    libx11-static \
    libxcb-static \
    libxkbfile-dev \

#
# Build XKeyboardConfig.
#
mkdir /tmp/xkb
log "Downloading XKeyboardConfig..."
curl -# -L ${XKEYBOARDCONFIG_URL} | tar -xj --strip 1 -C /tmp/xkb
log "Configuring XKeyboardConfig..."
(
    cd /tmp/xkb && abuild-meson . build
)
log "Compiling XKeyboardConfig..."
meson compile -C /tmp/xkb/build
log "Installing XKeyboardConfig..."
DESTDIR="/tmp/xkb-install" meson install --no-rebuild -C /tmp/xkb/build

log "Stripping XKeyboardConfig..."
# We keep only the filesi needed by Xvnc.
TO_KEEP="
    geometry/pc
    symbols/pc
    symbols/us
    symbols/srvr_ctrl
    symbols/keypad
    symbols/altwin
    symbols/inet
    compat/accessx
    compat/basic
    compat/caps
    compat/complete
    compat/iso9995
    compat/ledcaps
    compat/lednum
    compat/ledscroll
    compat/level5
    compat/misc
    compat/mousekeys
    compat/xfree86
    keycodes/evdev
    keycodes/aliases
    types/basic
    types/complete
    types/extra
    types/iso9995
    types/level5
    types/mousekeys
    types/numpad
    types/pc
    rules/evdev
"
find /tmp/xkb-install/usr/share/X11/xkb -mindepth 2 -maxdepth 2 -type d -print -exec rm -r {} ';'
find /tmp/xkb-install/usr/share/X11/xkb -mindepth 1 ! -type d $(printf "! -wholename /tmp/xkb-install/usr/share/X11/xkb/%s " $(echo "$TO_KEEP")) -print -delete

#
# Build xkbcomp.
#
mkdir /tmp/xkbcomp
log "Downloading xkbcomp..."
curl -# -L ${XKBCOMP_URL} | tar -xj --strip 1 -C /tmp/xkbcomp

log "Configuring xkbcomp..."
(
    cd /tmp/xkbcomp && LIBS="$LDFLAGS" ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
)

log "Compiling xkbcomp..."
make -C /tmp/xkbcomp -j$(nproc)

log "Installing xkbcomp..."
make DESTDIR=/tmp/xkbcomp-install -C /tmp/xkbcomp install

