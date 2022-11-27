#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

if is-bool-val-true "${DARK_MODE:-0}"; then
    cat /opt/base/etc/jwm/dark.jwmrc
else
    cat /opt/base/etc/jwm/light.jwmrc
fi
