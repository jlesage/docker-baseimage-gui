#!/usr/bin/with-contenv sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Adjust nginx virtual server configuration.
cp /defaults/default_site.conf /etc/nginx/
if [ "${SECURE_CONNECTION:-0}" -eq 1 ]; then
    sed-patch 's/$SECURE_CONNECTION/ssl/' /etc/nginx/default_site.conf
else
    sed-patch 's/$SECURE_CONNECTION//' /etc/nginx/default_site.conf
    sed-patch '/^[\t]ssl_certificate/d' /etc/nginx/default_site.conf
    sed-patch '/^[\t]ssl_dhparam/d' /etc/nginx/default_site.conf
fi

# Make sure required directories exist.
s6-setuidgid $USER_ID:$GROUP_ID mkdir -p /config/log/nginx

# vim: set ft=sh :
