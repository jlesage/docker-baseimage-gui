#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Place the application's name in web interface.
cp /opt/novnc/index.vnc /opt/novnc/index.html
sed-patch "s/\$DESKTOP/$APP_NAME/g" /opt/novnc/index.html

# Make sure the file has the right permissions.
chmod 644 /opt/novnc/index.html

# vim:ft=sh:ts=4:sw=4:et:sts=4
