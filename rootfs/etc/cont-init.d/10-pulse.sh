#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Nothing to do if audio support is disabled.
if is-bool-val-false "${WEB_AUDIO:-0}"; then
    exit 0
fi

# Create a new random cookie.
dd if=/dev/urandom of="$PULSE_COOKIE" bs=256 count=1 2>/dev/null

# Adjust ownership and permissions.
chmod 400 "$PULSE_COOKIE"
chown $USER_ID:$GROUP_ID "$PULSE_COOKIE"
