#!/usr/bin/with-contenv sh

#
# Add the app user to the password and group databases.  This is needed just to
# make sure that mapping between the user/group ID and its name is possible.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

echo "$APP_USER:x:$USER_ID:$GROUP_ID::/home/$APP_USER:/sbin/nologin" >> /etc/passwd
echo "$APP_USER:x:$GROUP_ID:" >> /etc/group

# vim: set ft=sh :
