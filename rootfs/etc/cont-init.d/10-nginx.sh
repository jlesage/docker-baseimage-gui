#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Adjust nginx virtual server configuration.
cp /defaults/default_site.conf /etc/nginx/
if [ "${SECURE_CONNECTION:-0}" -eq 0 ]; then
    sed-patch 's/ssl default_server/default_server/g' /etc/nginx/default_site.conf
    sed-patch '/^[\t]ssl_certificate/d' /etc/nginx/default_site.conf
    sed-patch '/^[\t]ssl_dhparam/d' /etc/nginx/default_site.conf
    sed-patch 's/:5950;/:5900;/' /etc/nginx/default_site.conf
fi
if ! ifconfig -a | grep -wq inet6; then
    sed-patch '/^[\t]listen \[::\]:5800 /d' /etc/nginx/default_site.conf
fi

# Make sure required directories exist.
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
