#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Nothing to do if web notification support is disabled.
if is-bool-val-false "${WEB_NOTIFICATION:-0}"; then
    exit 0
fi

# Verify that secure connection is enabled.
if is-bool-val-false "${SECURE_CONNECTION:-0}"; then
    echo "ERROR: web notification support requires secure web access to be enabled."
    echo "       make sure to set SECURE_CONNECTION=1 environment variable."
    exit 1
fi

# vim:ft=sh:ts=4:sw=4:et:sts=4
