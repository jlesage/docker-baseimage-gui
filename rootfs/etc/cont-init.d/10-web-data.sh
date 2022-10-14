#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

WEB_DATA_FILE="/tmp/.web_data.json"

rm -f "$WEB_DATA_FILE"

# Beginning of the JSON file.
printf '{\n' >> "$WEB_DATA_FILE"

# Add application name.
printf '    "applicationName": "%s"' "$APP_NAME" >> "$WEB_DATA_FILE"

# Add application version.
if [ -n "${APP_VERSION:-}" ]; then
    printf ',\n    "applicationVersion": "%s"' "$APP_VERSION" >> "$WEB_DATA_FILE"
fi

# Add Docker image version.
if [ -n "${DOCKER_IMAGE_VERSION:-}" ]; then
    printf ',\n    "dockerImageVersion": "%s"' "$DOCKER_IMAGE_VERSION" >> "$WEB_DATA_FILE"
fi

# Add dark mode.
if [ "${DARK_MODE:-0}" -eq 1 ]; then
    printf ',\n    "darkMode": true' >> "$WEB_DATA_FILE"
else
    printf ',\n    "darkMode": false' >> "$WEB_DATA_FILE"
fi

# End of the JSON file.
printf '\n}\n' >> "$WEB_DATA_FILE"

# Make sure the file has the right permissions.
chmod 444 "$WEB_DATA_FILE"

# vim:ft=sh:ts=4:sw=4:et:sts=4
