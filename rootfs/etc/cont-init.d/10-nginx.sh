#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

#
# Adjust nginx virtual server configuration.
#

# First, restore default configuration.
cp /defaults/default_site.conf /etc/nginx/
rm -f /etc/nginx/default_stream.conf

# Adjust SSL related configuration.
if [ "${SECURE_CONNECTION:-0}" -eq 0 ]; then
    # Secure connection disabled: remove ssl related setting from the site
    # config.
    sed-patch 's/ssl default_server/default_server/g' /etc/nginx/default_site.conf
    sed-patch '/^[\t]ssl_certificate/d' /etc/nginx/default_site.conf
    sed-patch '/^[\t]ssl_dhparam/d' /etc/nginx/default_site.conf
elif [ "${SECURE_CONNECTION_VNC_METHOD:-SSL}" = "SSL" ]; then
    # SSL secure connection enabled: activate the default stream config.
    if [ "${VNC_LISTENING_PORT:-5900}" -ne -1 ]; then
        cp /defaults/default_stream.conf /etc/nginx/default_stream.conf
        if [ "${VNC_LISTENING_PORT:-5900}" -ne 5900 ]; then
            sed-patch "g/5900/$VNC_LISTENING_PORT/g" /etc/nginx/default_stream.conf
        fi
    fi
fi

# Adust listening port.
if [ "${WEB_LISTENING_PORT:-5800}" -eq -1 ]; then
    # Port disabled: listen only on a unix socket to make nginx happy.
    sed-patch '/^[\t]listen \[::\]:5800 /d' /etc/nginx/default_site.conf
    sed-patch 's|5800|unix:/var/run/nginx/nginx.sock|g' /etc/nginx/default_site.conf
else
    # Disable IPv6 listening if not supported.
    if ! ifconfig -a | grep -wq inet6; then
        sed-patch '/^[\t]listen \[::\]:5800 /d' /etc/nginx/default_site.conf
    fi

    # Set the configured listening port.
    if [ "${WEB_LISTENING_PORT:-5800}" -ne 5800 ]; then
        sed-patch "s/5800/$WEB_LISTENING_PORT/g" /etc/nginx/default_site.conf
    fi
fi

#
# Make sure required directories exist.
#
NGINX_DIRS="\
    /config/log/nginx \
    /var/run/nginx \
    /var/tmp/nginx \
"

for DIR in $NGINX_DIRS
do
    mkdir -p "$DIR"
    chown $USER_ID:$GROUP_ID "$DIR"
done

# vim:ft=sh:ts=4:sw=4:et:sts=4
