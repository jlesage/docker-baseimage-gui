#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

APP_NAME="${APP_NAME:-DockerApp}"
UNIQUE_VERSION_FILE="/tmp/.web_unique_version"

# Content hash of the web root plus APP_NAME. Paths are included so adds,
# removes, and renames are detected; mtimes are not.
UNIQUE_VERSION="$(
    {
        find /opt/noVNC -type f -exec sha256sum {} + | sort
        printf 'APP_NAME=%s\n' "${APP_NAME}"
    } | sha256sum | cut -c1-10
)"

printf '%s\n' "${UNIQUE_VERSION}" > "${UNIQUE_VERSION_FILE}"
chmod 444 "${UNIQUE_VERSION_FILE}"

# vim:ft=sh:ts=4:sw=4:et:sts=4
