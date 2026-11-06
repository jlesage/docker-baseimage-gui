#!/bin/sh
#
# Build the viewer-cursor theme from the Breeze cursor pictures.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

#
# Install required packages.
#
apk --no-cache add \
    python3 \
    breeze-cursors

python3 "$SCRIPT_DIR/gen-cursors.py" \
    --cursors /usr/share/icons/breeze_cursors/cursors \
    --out /tmp/viewer-cursor-theme
