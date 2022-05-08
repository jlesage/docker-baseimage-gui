#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

FONTCONFIG_CACHE_DIR=/config/xdg/cache/fontconfig

# Make sure the fontconfig cache directory exists to prevent JWM displaying the
# message 'Fontconfig error: No writable cache directories'.
if [ ! -d "$FONTCONFIG_CACHE_DIR" ]; then
    mkdir -p "$FONTCONFIG_CACHE_DIR"
    chown $USER_ID:$GROUP_ID "$FONTCONFIG_CACHE_DIR"
fi
