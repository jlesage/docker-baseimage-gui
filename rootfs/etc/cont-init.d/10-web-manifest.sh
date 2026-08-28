#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

WEB_MANIFEST_FILE="/tmp/.site.webmanifest"

# Escape a string for inclusion in a JSON string value.
json_escape() {
    printf '%s' "$1" | awk '
    BEGIN { ORS = "" }
    {
        gsub(/\\/, "\\\\")
        gsub(/"/, "\\\"")
        gsub(/\t/, "\\t")
        gsub(/\r/, "\\r")
        if (NR > 1) print "\\n"
        print
    }'
}

APP_NAME_JSON="$(json_escape "${APP_NAME}")"
DESCRIPTION_JSON="$(json_escape "Opens the graphical interface of ${APP_NAME} running in a Docker container.")"

rm -f "${WEB_MANIFEST_FILE}"

cat > "${WEB_MANIFEST_FILE}" <<EOF
{
    "name": "${APP_NAME_JSON}",
    "short_name": "${APP_NAME_JSON}",
    "description": "${DESCRIPTION_JSON}",
    "start_url": "./",
    "scope": "./",
    "display": "standalone",
    "background_color": "#313131",
    "theme_color": "#313131",
    "icons": [
        { "src": "android-chrome-192x192.png", "type": "image/png", "sizes": "192x192" },
        { "src": "android-chrome-512x512.png", "type": "image/png", "sizes": "512x512" },
        { "src": "android-chrome-512x512-mask.png", "type": "image/png", "sizes": "512x512", "purpose": "maskable" }
    ]
}
EOF

# Make sure the file has the right permissions.
chmod 444 "${WEB_MANIFEST_FILE}"

# vim:ft=sh:ts=4:sw=4:et:sts=4
