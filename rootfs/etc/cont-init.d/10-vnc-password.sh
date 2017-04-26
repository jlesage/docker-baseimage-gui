#!/usr/bin/with-contenv sh

#
# Handle the VNC password.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# If password is saved in clear, obfuscate it to a new file.
if [ -f /config/.vncpass_clear ]; then
    /usr/bin/x11vnc -storepasswd "$( cat /config/.vncpass_clear )" /config/.vncpass
    rm /config/.vncpass_clear
fi

# If password is set in a file, use it.  Else, use the password stored in the
# environment variable.
if [ -f /config/.vncpass ]; then
    cp /config/.vncpass /root/.vncpass
elif [ "${VNC_PASSWORD:-UNSET}" != "UNSET" ]; then
    /usr/bin/x11vnc -storepasswd "$VNC_PASSWORD" /root/.vncpass
else
    rm -f /root/.vncpass
fi

# Adjust ownership and permissions of password files.
[ -f /config/.vncpass ] && chown $USER_ID:$GROUP_ID /config/.vncpass
[ -f /config/.vncpass ] && chmod 600 /config/.vncpass
[ -f /root/.vncpass ]   && chmod 400 /root/.vncpass

return 0

# vim: set ft=sh :
