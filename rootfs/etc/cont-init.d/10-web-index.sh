#!/usr/bin/with-contenv sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Place the application's name in web interface.
cp /opt/novnc/index.vnc /opt/novnc/index.html
sed-patch "s/\$DESKTOP/$APP_NAME/g" /opt/novnc/index.html

# vim: set ft=sh :
