#!/usr/bin/with-contenv sh

#
# Add the 'guiapp' user to the password and group databases.  This is needed
# just to make sure that mapping between the user/group ID and its name is
# possible.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

echo "guiapp:x:$USER_ID:$GROUP_ID::/home/guiapp:/sbin/nologin" >> /etc/passwd
echo "guiapp:x:$GROUP_ID:" >> /etc/group

# vim: set ft=sh :
