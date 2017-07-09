#!/usr/bin/with-contenv sh

#
# Adjust ownership of files and directories owned by the app user.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

chown -R $USER_ID:$GROUP_ID /home/$APP_USER
chown -R $USER_ID:$GROUP_ID /config

# vim: set ft=sh :
