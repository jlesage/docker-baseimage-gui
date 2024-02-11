#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

PASSWORD_FILE="/config/webauth-htpasswd"

# Nothing to do if web authentication is disabled.
if is-bool-val-false "${WEB_AUTHENTICATION:-0}"; then
    exit 0
fi

# Verify that secure connection is enabled.
if is-bool-val-false "${SECURE_CONNECTION:-0}"; then
    echo "ERROR: web authentication requires secure connection to be enabled."
    echo "       make sure to set SECURE_CONNECTION=1 environment variable."
    exit 1
fi

# Make sure the password db exists.
[ -f "$PASSWORD_FILE" ] || touch "$PASSWORD_FILE"

# Set permissions of the password db.
chmod 600 "$PASSWORD_FILE"

if [ -z "${WEB_AUTHENTICATION_USERNAME:-}" ] && [ -z "${WEB_AUTHENTICATION_PASSWORD:-}" ]; then
    if [ "$(stat -c "%s" "$PASSWORD_FILE")" -eq 0 ]; then
        echo "WARNING: no user configured for web authentication"
    fi
elif [ -z "${WEB_AUTHENTICATION_USERNAME:-}" ] || [ -z "${WEB_AUTHENTICATION_PASSWORD:-}" ]; then
    echo "ERROR: missing username/password for configured web authentication user"
    echo "       make sure that both WEB_AUTHENTICATION_USERNAME and WEB_AUTHENTICATION_PASSWORD"
    echo "       environment variables are set."
    exit 1
else
    # Add password to database.
    echo "$WEB_AUTHENTICATION_PASSWORD" | htpasswd -i "$PASSWORD_FILE" "$WEB_AUTHENTICATION_USERNAME"
fi

# vim:ft=sh:ts=4:sw=4:et:sts=4
