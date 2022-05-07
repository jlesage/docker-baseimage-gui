#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

WEB_DATA_FILE="/tmp/.web_data.json"

rm -f "$WEB_DATA_FILE"

# Beginning of the JSON file.
echo "{" >> "$WEB_DATA_FILE"

# Add application name.
echo -ne "    \"applicationName\": \"$APP_NAME\"" >> "$WEB_DATA_FILE"

# Add application version.
if [ -n "${APP_VERSION:-}" ]; then
    echo -ne ",\n    \"applicationVersion\": \"$APP_VERSION\"" >> "$WEB_DATA_FILE"
fi

# Add Docker image version.
if [ -n "${DOCKER_IMAGE_VERSION:-}" ]; then
    echo -ne ",\n    \"dockerImageVersion\": \"$DOCKER_IMAGE_VERSION\"" >> "$WEB_DATA_FILE"
fi

# Add dark mode.
if [ "${DARK_MODE:-0}" -eq 1 ]; then
    echo -ne ",\n    \"darkMode\": true" >> "$WEB_DATA_FILE"
else
    echo -ne ",\n    \"darkMode\": false" >> "$WEB_DATA_FILE"
fi

# End of the JSON file.
echo -ne "\n" >> "$WEB_DATA_FILE"
echo "}" >> "$WEB_DATA_FILE"

# Make sure the file has the right permissions.
chmod 444 "$WEB_DATA_FILE"

# vim:ft=sh:ts=4:sw=4:et:sts=4
