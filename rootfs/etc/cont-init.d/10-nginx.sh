#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

#
# Adjust nginx virtual server configuration.
#

NGINX_DIRS="\
    /config/log \
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
FMGR_CONF=/var/tmp/nginx/fmgr.conf
NOTIF_CONF=/var/tmp/nginx/notif.conf
TERM_CONF=/var/tmp/nginx/term.conf

# Make sure required directories exist.
for dir in ${NGINX_DIRS}; do
    [ -d "${dir}" ] || mkdir --mode=755 "${dir}"
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

    # Determine the listen address.
    if is-bool-val-true "${WEB_LOCALHOST_ONLY:-0}"; then
        LISTEN_ADDR4="127.0.0.1"
        LISTEN_ADDR6="[::1]"
    else
        LISTEN_ADDR4="0.0.0.0"
        LISTEN_ADDR6="[::]"
    fi

    # Add the listen directive.
    echo "listen ${LISTEN_ADDR4}:${LISTEN_PORT} ${LISTEN_SSL} default_server;" >> "${LISTEN_CONF}"

    # Add the listen directive for IPv6.
    if [ "${WEB_LISTENING_PORT:-5800}" -ne -1 ] && ifconfig -a | grep -wq inet6; then
        echo "listen ${LISTEN_ADDR6}:${LISTEN_PORT} ${LISTEN_SSL} default_server;" >> "${LISTEN_CONF}"
    fi
fi

# Handle SSL configuration.
if is-bool-val-true "${SECURE_CONNECTION:-0}"; then
    cp -a /opt/base/etc/nginx/include/ssl.conf "${SSL_CONF}"
fi

# Handle stream configuration.
# The stream config is needed only when secure connection is enabled, with the
# VNC method set to SSL.
if is-bool-val-true "${SECURE_CONNECTION:-0}" && [ "${SECURE_CONNECTION_VNC_METHOD:-SSL}" = "SSL" ] && [ "${VNC_LISTENING_PORT:-5900}" -ne -1 ]; then
    # Copy the default config.
    cp -a /opt/base/etc/nginx/include/stream.conf "${STREAM_CONF}"

    # Generate the listen directive for stream config.
    echo "listen ${VNC_LISTENING_PORT:-5900} ssl;" >> "${STREAM_LISTEN_CONF}"
fi

# Handle configuration for audio support.
if is-bool-val-true "${WEB_AUDIO:-0}"; then
    cp -a /opt/base/etc/nginx/include/audio.conf "${AUDIO_CONF}"
fi

# Handle configuration for web authentication.
if is-bool-val-true "${WEB_AUTHENTICATION:-0}"; then
    cp -a /opt/base/etc/nginx/include/auth.conf "${AUTH_CONF}"
else
    # Feature is disabled, so we need to prevent access to the login page.
    {
        printf "location /login/ {\n"
        printf "\treturn 404;\n"
        printf "}\n"
    } >> "${AUTH_CONF}"
fi

# Handle configuration for file manager support.
if is-bool-val-true "${WEB_FILE_MANAGER:-0}"; then
    cp -a /opt/base/etc/nginx/include/fmgr.conf "${FMGR_CONF}"
fi

# Handle configuration for web notification support.
if is-bool-val-true "${WEB_NOTIFICATION:-0}"; then
    cp -a /opt/base/etc/nginx/include/notif.conf "${NOTIF_CONF}"
fi

# Handle configuration for web terminal support.
if is-bool-val-true "${WEB_TERMINAL:-0}"; then
    cp -a /opt/base/etc/nginx/include/terminal.conf "${TERM_CONF}"
fi

# Make sure required directories are properly owned.
for dir in ${NGINX_DIRS}; do
    chown "${USER_ID}:${GROUP_ID}" "${dir}"
done

# vim:ft=sh:ts=4:sw=4:et:sts=4
