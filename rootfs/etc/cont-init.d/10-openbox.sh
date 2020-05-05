#!/usr/bin/with-contenv sh

#
# Handle the OpenBox configuration.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Ajust OpenBox configuration to enable window decorations in all windows.
cp /defaults/rc.xml /etc/xdg/openbox/rc.xml
if [ "${USE_WINDOW_DECORATION:-0}" -eq 1 ]; then
    sed-patch 's/<decor>no<\/decor>/<decor>yes<\/decor>/g' /etc/xdg/openbox/rc.xml
fi

# vim: set ft=sh :
