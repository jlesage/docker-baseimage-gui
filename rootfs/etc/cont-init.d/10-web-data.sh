#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

is_number() {
    case "${1:-}" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

WEB_DATA_FILE="/tmp/.webdata.js"

rm -f "$WEB_DATA_FILE"

# Beginning of the JavaScript file.
printf 'const WebData = {\n' >> "$WEB_DATA_FILE"

# Add application name.
printf '    applicationName: "%s"' "$APP_NAME" >> "$WEB_DATA_FILE"

# Add application version.
if [ -n "${APP_VERSION:-}" ]; then
    printf ',\n    applicationVersion: "%s"' "$APP_VERSION" >> "$WEB_DATA_FILE"
fi

# Add Docker image version.
if [ -n "${DOCKER_IMAGE_VERSION:-}" ]; then
    printf ',\n    dockerImageVersion: "%s"' "$DOCKER_IMAGE_VERSION" >> "$WEB_DATA_FILE"
fi

# Add dark mode.
if is-bool-val-true "${DARK_MODE:-0}"; then
    printf ',\n    darkMode: true' >> "$WEB_DATA_FILE"
else
    printf ',\n    darkMode: false' >> "$WEB_DATA_FILE"
fi

# Add application's window width.
if is_number "${DISPLAY_WIDTH:-}"; then
    printf ',\n    applicationWindowWidth: %s' "$DISPLAY_WIDTH" >> "$WEB_DATA_FILE"
fi

# Add application's window height.
if is_number "${DISPLAY_HEIGHT:-}"; then
    printf ',\n    applicationWindowHeight: %s' "$DISPLAY_HEIGHT" >> "$WEB_DATA_FILE"
fi

# End of the JavaScript file.
printf '\n};\n' >> "$WEB_DATA_FILE"
printf 'export default WebData;\n' >> "$WEB_DATA_FILE"

# Make sure the file has the right permissions.
chmod 444 "$WEB_DATA_FILE"

# vim:ft=sh:ts=4:sw=4:et:sts=4
