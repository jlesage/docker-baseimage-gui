#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

FONTCONFIG_CACHE_DIR=/config/xdg/cache/fontconfig

# Make sure the fontconfig cache directory exists.  This prevent the error
# "Fontconfig error: No writable cache directories" that programs might
# raise (e.g openbox).
if [ ! -d "${FONTCONFIG_CACHE_DIR}" ]; then
    mkdir -p "$(dirname "${FONTCONFIG_CACHE_DIR}")"
    cp -a /opt/base/share/fontconfig/cache "${FONTCONFIG_CACHE_DIR}"
fi

# vim:ft=sh:ts=4:sw=4:et:sts=4
