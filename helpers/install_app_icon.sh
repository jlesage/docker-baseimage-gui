#!/bin/sh
#
# Helper script to generate and install favicons.
#
# This is based on the "How to Favicon in 2024" guide that can be found at:
# https://evilmartians.com/chronicles/how-to-favicon-in-2021-six-files-that-fit-most-needs
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

WORKDIR=$(mktemp -d)

APP_ICON_URL=""
ICONS_DIR="/opt/noVNC/app/images/icons"
HTML_FILE="/opt/noVNC/index.html"
INSTALL_MISSING_TOOLS=1
UNIQUE_VERSION="$(date | md5sum | cut -c1-10)"

usage() {
    if [ -n "$*" ]; then
        echo "$*"
        echo
    fi

    echo "usage: $(basename $0) ICON_URL [OPTIONS...]

Generate and install favicons.

Arguments:
  ICON_URL   URL pointing to the master picture, in PNG format.  All favicons are
             generated from this picture.

Options:
  --icons-dir         Directory where to put the generated icons.  Default: /opt/noVNC/app/images/icons
  --html-file         Path to the HTML file where to insert the HTML code.  Default: /opt/noVNC/index.html
  --no-tools-install  Do not automatically install missing tools.
"

    exit 1
}

die() {
    echo "Failed to generate favicons: $*."
    exit 1
}

install_build_dependencies_alpine() {
    INSTALLED_PKGS=""
    if [ -z "$(which curl)" ]; then
        INSTALLED_PKGS="$INSTALLED_PKGS curl"
    fi
    if [ -z "$(which magick)" ] && [ -z "$(which convert)" ]; then
        INSTALLED_PKGS="$INSTALLED_PKGS imagemagick"
    fi
    if [ -z "$(which sed)" ] || ! sed --version | grep -q "(GNU sed)"; then
        INSTALLED_PKGS="$INSTALLED_PKGS sed"
    fi

    if [ -n "$INSTALLED_PKGS" ]; then
        add-pkg --virtual rfg-build-dependencies $INSTALLED_PKGS
    fi
}

install_build_dependencies_debian() {
    INSTALLED_PKGS=""
    if [ -z "$(which curl)" ]; then
        INSTALLED_PKGS="$INSTALLED_PKGS curl ca-certificates"
    fi
    if [ -z "$(which magick)" ] && [ -z "$(which convert)" ]; then
        INSTALLED_PKGS="$INSTALLED_PKGS imagemagick"
    fi

    if [ -n "$INSTALLED_PKGS" ]; then
        add-pkg --virtual rfg-build-dependencies $INSTALLED_PKGS
    fi
}

install_build_dependencies() {
    if [ "$INSTALL_MISSING_TOOLS" -eq 1 ]; then
        if [ -n "$(which apk)" ]; then
            install_build_dependencies_alpine
        else
            install_build_dependencies_debian
        fi
    fi
}

uninstall_build_dependencies() {
    if [ "$INSTALL_MISSING_TOOLS" -eq 1 ]; then
        if [ -n "$INSTALLED_PKGS" ]; then
            del-pkg rfg-build-dependencies
        fi
    fi
}

cleanup() {
    rm -rf "$WORKDIR"
}

# Parse arguments.
while [ "$#" -ne 0 ]
do
    case "$1" in
        --icons-dir)
            ICONS_DIR="${2:-}"
            if [ -z "$ICONS_DIR" ]; then
                usage "Icons directory missing."
            fi
            shift 2
            ;;
        --html-file)
            HTML_FILE="${2:-}"
            if [ -z "$HTML_FILE" ]; then
                usage "HTML file path missing."
            fi
            shift 2
            ;;
        --no-tools-install)
            INSTALL_MISSING_TOOLS=0
            shift
            ;;
        -h|--help)
            usage
            ;;
        --*)
            usage "Unknown argument \"$1\"."
            ;;
        *)
            if [ -z "$APP_ICON_URL"]; then
                APP_ICON_URL="$1"
                shift
            else
                usage "Unknown argument \"$1\"."
            fi
            ;;
    esac
done

[ -n "$APP_ICON_URL" ] || usage "Icon URL is missing."
[ -f "$HTML_FILE" ] || die "HTML file not found: $HTML_FILE"

# Check if URL is pointing to a local file.
if [ -f "$APP_ICON_URL" ]; then
    ICON_URL_IS_LOCAL_PATH=true
elif [ "${APP_ICON_URL#file://}" != "$APP_ICON_URL" ]; then
    ICON_URL_IS_LOCAL_PATH=true
    APP_ICON_URL="${APP_ICON_URL#file://}"
    if [ ! -f "$APP_ICON_URL" ]; then
        die "$APP_ICON_URL: no such file"
    fi
else
    ICON_URL_IS_LOCAL_PATH=false
fi

echo "Installing dependencies..."
install_build_dependencies

# Clear any previously generated icons.
rm -rf "$ICONS_DIR"
mkdir -p "$ICONS_DIR"

# Download the master icon.
if $ICON_URL_IS_LOCAL_PATH; then
    cp "$APP_ICON_URL" "$ICONS_DIR"/master_icon.png
else
    curl -sS -L -o "$ICONS_DIR"/master_icon.png "$APP_ICON_URL"
fi

# Validate the master icon.
ICON_WIDTH="$(identify -ping -format '%w' "$ICONS_DIR"/master_icon.png)"
ICON_HEIGHT="$(identify -ping -format '%h' "$ICONS_DIR"/master_icon.png)"
if [ "$ICON_WIDTH" != "$ICON_HEIGHT" ]; then
    echo "WARNING: The master icon should be square."
fi
if [ "$ICON_WIDTH" -lt 512 ] || [ "$ICON_HEIGHT" -lt 512 ]; then
    echo "WARNING: The master icon should be at least 512x512 (current size: ${ICON_WIDTH}x${ICON_HEIGHT}."
fi

echo "Generating favicons..."

MAGICK_CMD="convert"
if [ -n "$(which magick)" ]; then
    MAGICK_CMD="magick"
fi

# favicon.ico for legacy browsers.
# ICO can pack files with different resolutions, but it is recommended to stick
# to a single 32x32 image.
$MAGICK_CMD "$ICONS_DIR"/master_icon.png -define icon:auto-resize=32 -colors 256 "$ICONS_DIR"/favicon.ico

# Web app manifest with 192×192 and 512×512 PNG icons for Android devices.
# The maskable icon should have bigger paddings around the icon so it can be
# cropped by the launcher to fit its design.
$MAGICK_CMD "$ICONS_DIR"/master_icon.png -resize 192x192 "$ICONS_DIR"/android-chrome-192x192.png
$MAGICK_CMD "$ICONS_DIR"/master_icon.png -resize 512x512 "$ICONS_DIR"/android-chrome-512x512.png
$MAGICK_CMD "$ICONS_DIR"/master_icon.png -resize 409x409 -gravity center -background transparent -extent 512x512 "$ICONS_DIR"/android-chrome-512x512-mask.png
cat <<EOF > "$ICONS_DIR"/site.webmanifest
{
  "icons": [
    { "src": "/android-chrome-192x192.png?v=$UNIQUE_VERSION", "type": "image/png", "sizes": "192x192" },
    { "src": "/android-chrome-512x512.png?v=$UNIQUE_VERSION", "type": "image/png", "sizes": "512x512" },
    { "src": "/android-chrome-512x512-mask.png?v=$UNIQUE_VERSION", "type": "image/png", "sizes": "512x512", "purpose": "maskable" }
  ]
}
EOF

# 180×180 PNG image for Apple devices.
# Apple touch icon will look better if a 20px padding around the icon is used
# and add with some background color.
$MAGICK_CMD "$ICONS_DIR"/master_icon.png -resize 140x140 -gravity center -background transparent -extent 180x180 -background white -alpha remove -alpha off "$ICONS_DIR"/apple-touch-icon.png

# Create the HTML code to be inserted.
cat <<EOF > "$WORKDIR"/htmlCode
    <link rel="icon" href="favicon.ico?v=$UNIQUE_VERSION" sizes="32x32">
    <link rel="apple-touch-icon" href="apple-touch-icon.png?v=$UNIQUE_VERSION">
    <link rel="manifest" href="site.webmanifest?v=$UNIQUE_VERSION">
EOF

echo "Adjusting HTML page..."
cat "$HTML_FILE" | sed -ne "/<!-- BEGIN Favicons -->/ {p; r $WORKDIR/htmlCode" -e ":a; n; /<!-- END Favicons -->/ {p; b}; ba}; p" > "$WORKDIR"/tmp.html
if diff "$WORKDIR"/tmp.html "$HTML_FILE" > /dev/null 2>&1; then
    die "Could not insert HTML code."
fi
mv "$WORKDIR"/tmp.html "$HTML_FILE"

echo "Removing dependencies..."
uninstall_build_dependencies

echo "Cleaning..."
cleanup

echo "Favicons successfully generated."

# vim:ft=sh:ts=4:sw=4:et:sts=4
