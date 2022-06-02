#!/bin/sh
#
# Setup dark mode.
#
# To activate dark mode, the following actions are required:
#   - For GTK applications:
#     - Set environment variable GTK_THEME=Adwaita:dark.
#       - This is done by /etc/cont-env.d/GTK_THEME.
#   - For QT applications:
#     - Set enviroment variable QT_QPA_PLATFORMTHEME=qt5ct.
#       - This is done by /etc/cont-env.d/QT_QPA_PLATFORMTHEME.
#     - Install qt5ct configuration file.
#       - This is done here.
#     - Install the QT Configuration Tool (qt5ct) and Adwaita style/theme.
#       - This should be done by the application's Dockerfile: integrating
#         the required libraries into the baseimage would pull too much
#         dependencies.

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

mkdir -p "$XDG_CONFIG_HOME"/qt5ct

if [ "${DARK_MODE:-0}" -eq 1 ]; then
    # Dark mode enabled.
    MODE=dark
else
    # Dark mode *not* enabled.
    MODE=light
fi

# Install the correct qt5ct config file.
cp /defaults/qt5ct-$MODE.conf "$XDG_CONFIG_HOME"/qt5ct/qt5ct.conf

# vim:ft=sh:ts=4:sw=4:et:sts=4
