#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

#
# Adjust nginx virtual server configuration.
#

NGINX_DIRS="\
    /config/log/nginx \
    /var/run/nginx \
    /var/tmp/nginx \
"
DEFAULT_SITE_CONF=/var/tmp/nginx/default_site.conf
DEFAULT_STREAM_CONF=/var/tmp/nginx/default_stream.conf

# Make sure required directories exist.
for DIR in $NGINX_DIRS; do
    mkdir -p "$DIR"
done

# First, restore default configuration files.
cp /defaults/default_site.conf "$DEFAULT_SITE_CONF"
rm -f "$DEFAULT_STREAM_CONF"

# Adjust SSL related configuration.
if is-bool-val-false "${SECURE_CONNECTION:-0}"; then
    # Secure connection disabled: remove ssl related setting from the site
    # config.
    sed-patch 's/ssl default_server/default_server/g' "$DEFAULT_SITE_CONF"
    sed-patch '/^[\t]ssl_certificate/d' "$DEFAULT_SITE_CONF"
    sed-patch '/^[\t]ssl_dhparam/d' "$DEFAULT_SITE_CONF"
elif [ "${SECURE_CONNECTION_VNC_METHOD:-SSL}" = "SSL" ]; then
    # SSL secure connection enabled: activate the default stream config.
    if [ "${VNC_LISTENING_PORT:-5900}" -ne -1 ]; then
        cp /defaults/default_stream.conf "$DEFAULT_STREAM_CONF"
        if [ "${VNC_LISTENING_PORT:-5900}" -ne 5900 ]; then
            sed-patch "s/5900/$VNC_LISTENING_PORT/g" "$DEFAULT_STREAM_CONF"
        fi
    fi
fi

# Adust listening port.
if [ "${WEB_LISTENING_PORT:-5800}" -eq -1 ]; then
    # Port disabled: listen only on a unix socket to make nginx happy.
    sed-patch '/^[\t]listen \[::\]:5800 /d' "$DEFAULT_SITE_CONF"
    sed-patch 's|5800|unix:/var/run/nginx/nginx.sock|g' "$DEFAULT_SITE_CONF"
else
    # Disable IPv6 listening if not supported.
    if ! ifconfig -a | grep -wq inet6; then
        sed-patch '/^[\t]listen \[::\]:5800 /d' "$DEFAULT_SITE_CONF"
    fi

    # Set the configured listening port.
    if [ "${WEB_LISTENING_PORT:-5800}" -ne 5800 ]; then
        sed-patch "s/5800/$WEB_LISTENING_PORT/g" "$DEFAULT_SITE_CONF"
    fi
fi

# Make sure required directories are properly owned.
for DIR in $NGINX_DIRS; do
    chown $USER_ID:$GROUP_ID "$DIR"
done

# vim:ft=sh:ts=4:sw=4:et:sts=4
