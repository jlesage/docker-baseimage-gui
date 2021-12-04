#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

if [ "${DARK_MODE:-0}" -eq 1 ]; then
    cat /etc/jwm/dark.jwmrc
else
    cat /etc/jwm/light.jwmrc
fi
