#!/bin/sh
#
# Helper script that builds a customized version of XKeyboard config files
# that are used by the X server. The goal is to prevent version mismatch issues
# that could occur when using XKeyboard config files installed to the "standard"
# location.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Define software versions.
# Use the same versions has Alpine 3.20.
# If the XKeyboardConfig version is too recent compared to xorgproto/libX11,
# xkbcomp will complain with warnings like "Could not resolve keysym ...".
XKEYBOARDCONFIG_VERSION=2.41

# Define software download URLs.
XKEYBOARDCONFIG_URL=https://www.x.org/archive/individual/data/xkeyboard-config/xkeyboard-config-${XKEYBOARDCONFIG_VERSION}.tar.xz

# Set same default compilation flags as abuild.
export CFLAGS="-Os -fomit-frame-pointer"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS="-Wl,--as-needed,-O1,--sort-common -Wl,--strip-all"

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
    abuild \
    meson \
    perl \
    xz \
"

log "Installing required Alpine packages..."
apk --no-cache add $HOST_PKGS

#
# Build XKeyboardConfig.
#
mkdir /tmp/xkb
log "Downloading XKeyboardConfig..."
curl -# -L -f ${XKEYBOARDCONFIG_URL} | tar -xJ --strip 1 -C /tmp/xkb
log "Configuring XKeyboardConfig..."
(
    cd /tmp/xkb && abuild-meson . build
)
log "Compiling XKeyboardConfig..."
meson compile -C /tmp/xkb/build
log "Installing XKeyboardConfig..."
DESTDIR="/tmp/xkb-install" meson install --no-rebuild -C /tmp/xkb/build

log "Stripping XKeyboardConfig..."
# We keep only the files needed by Xvnc.
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
# Cleanup.
#
log "Performing cleanup..."
apk --no-cache del $HOST_PKGS
apk --no-cache add util-linux # Linux tools still needed and they might be removed if pulled by dependencies.
rm -rf /tmp/xkb
