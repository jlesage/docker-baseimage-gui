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

LISTEN_CONF=/var/tmp/nginx/listen.conf
SSL_CONF=/var/tmp/nginx/ssl.conf
STREAM_CONF=/var/tmp/nginx/stream.conf
STREAM_LISTEN_CONF=/var/tmp/nginx/stream_listen.conf
AUDIO_CONF=/var/tmp/nginx/audio.conf
AUTH_CONF=/var/tmp/nginx/auth.conf

# Make sure required directories exist.
for DIR in $NGINX_DIRS; do
    mkdir -p "$DIR"
done

# First, clear all dynamic config files.
rm -f /var/tmp/nginx/*.conf

# Generate the listen directive for HTTP access.
if true; then
    # Determine the listen port.
    if [ "${WEB_LISTENING_PORT:-5800}" -eq -1 ]; then
        # Port disabled: listen only on a unix socket to make nginx happy.
        LISTEN_PORT="unix:/var/run/nginx/nginx.sock"
    else
        LISTEN_PORT="${WEB_LISTENING_PORT:-5800}"
    fi

    # Determine if secure port is used.
    if is-bool-val-true "${SECURE_CONNECTION:-0}"; then
        LISTEN_SSL="ssl"
    else
        LISTEN_SSL=
    fi

    # Add the listen directive.
    echo "listen $LISTEN_PORT $LISTEN_SSL default_server;" >> "$LISTEN_CONF"

    # Add the listen directive for IPv6.
    if [ "${WEB_LISTENING_PORT:-5800}" -ne -1 ] && ifconfig -a | grep -wq inet6; then
        echo "listen [::]:$LISTEN_PORT $LISTEN_SSL default_server;" >> "$LISTEN_CONF"
    fi
fi

# Handle SSL configuration.
if is-bool-val-true "${SECURE_CONNECTION:-0}"; then
    cp -a /defaults/default_ssl.conf "$SSL_CONF"
fi

# Handle stream configuration.
# The stream config is needed only when secure connection is enabled, with the
# VNC method set to SSL.
if is-bool-val-true "${SECURE_CONNECTION:-0}" && [ "${SECURE_CONNECTION_VNC_METHOD:-SSL}" = "SSL" ] && [ "${VNC_LISTENING_PORT:-5900}" -ne -1 ]
then
    # Copy the default config.
    cp -a /defaults/default_stream.conf "$STREAM_CONF"

    # Generate the listen directive for stream config.
    echo "listen ${VNC_LISTENING_PORT:-5900} ssl;" >> "$STREAM_LISTEN_CONF"
fi

# Handle configuration for audio support.
if is-bool-val-true "${WEB_AUDIO:-0}"; then
    cp -a /defaults/default_audio.conf "$AUDIO_CONF"
fi

# Handle configuration for web authentication.
if is-bool-val-true "${WEB_AUTHENTICATION:-0}"; then
    cp -a /defaults/default_auth.conf "$AUTH_CONF"
else
    # Feature is disabled, so we need to prevent access to the login page.
    printf "location /login/ {" >> "$AUTH_CONF"
    printf "\treturn 404;" >> "$AUTH_CONF"
    printf "}" >> "$AUTH_CONF"
fi

# Make sure required directories are properly owned.
for DIR in $NGINX_DIRS; do
    chown $USER_ID:$GROUP_ID "$DIR"
done

# vim:ft=sh:ts=4:sw=4:et:sts=4
