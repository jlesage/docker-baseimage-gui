#!/bin/sh

#
# Handle the VNC password.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# If password is saved in clear, obfuscate it to a new file.
if [ -f /config/.vncpass_clear ]; then
    echo "obfuscating VNC password..."
    rm -f /config/.vncpass
    cat /config/.vncpass_clear | /usr/bin/vncpasswd -f  > /config/.vncpass
    rm /config/.vncpass_clear
fi

# If password is set in a file, use it.  Else, use the password stored in the
# environment variable.
if [ -f /config/.vncpass ]; then
    echo "VNC password file found."
elif [ -n "${VNC_PASSWORD:-}" ]; then
    echo "creating VNC password file from environment variable..."
    echo "$VNC_PASSWORD" | /usr/bin/vncpasswd -f  > /tmp/.vncpass
    chmod 400 /tmp/.vncpass
fi

# Adjust ownership and permissions of password files.
if [ -f /config/.vncpass ]; then
   chown $USER_ID:$GROUP_ID /config/.vncpass
   chmod 400 /config/.vncpass
fi

# vim:ft=sh:ts=4:sw=4:et:sts=4
