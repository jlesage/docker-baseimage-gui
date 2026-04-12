#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

if is-bool-val-true "${WEB_TERMINAL:-0}"; then
    if [ ! -x "${WEB_TERMINAL_SHELL_PATH:-/bin/sh}" ]; then
        echo "ERROR: Web terminal shell path not found: ${WEB_TERMINAL_SHELL_PATH:-/bin/sh}"
        exit 1
    fi
fi

# vim:ft=sh:ts=4:sw=4:et:sts=4
