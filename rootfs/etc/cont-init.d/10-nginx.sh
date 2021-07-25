#!/usr/bin/with-contenv sh

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
if [ "${CAC_AUTH:-0}" -eq 1 ]; then
    sed-patch '19i \\tssl_client_certificate /config/certs/client.pem; \n\tssl_verify_client on; \n\tif ($ssl_client_s_dn !~ "CN=${CAC_Common_Name}") { \n\t\treturn 403; \n\t} \n' /etc/nginx/default_site.conf
fi
if ! ifconfig -a | grep -wq inet6; then
    sed-patch '/^[\t]listen \[::\]:5800 /d' /etc/nginx/default_site.conf
fi

# Make sure required directories exist.
s6-setuidgid $USER_ID:$GROUP_ID mkdir -p /config/log/nginx

# vim: set ft=sh :
