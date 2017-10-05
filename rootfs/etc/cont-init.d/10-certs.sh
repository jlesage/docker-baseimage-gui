#!/usr/bin/with-contenv sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

log() {
    echo "[cont-init.d] $(basename $0): $*"
}

# Exit now if secure connection not enabled.
[ "${SECURE_CONNECTION:-0}" -eq 1 ] || exit 0

CERT_DIR=/config/certs

s6-setuidgid $USER_ID:$GROUP_ID mkdir -p "$CERT_DIR"

# Generate DH parameters.
if [ ! -f "$CERT_DIR/dhparam.pem" ]; then
    if [ "${USE_DEFAULT_DH_PARAMS:-0}" -eq 0 ]; then
        log "Generating DH parameters (2048 bits), this is going to take a long time..."
        env HOME=/tmp s6-setuidgid $USER_ID:$GROUP_ID openssl dhparam \
            -out "$CERT_DIR/dhparam.pem" \
            2048 \
            > /dev/null 2>&1
    else
        cp /defaults/dhparam.pem "$CERT_DIR/dhparam.pem"
    fi
fi

# Generate certificate used by the WEB server (nginx).
if [ ! -f "$CERT_DIR/web-privkey.pem" ] && [ ! -f "$CERT_DIR/web-fullchain.pem" ]; then
    log "Generating self-signed certificate for WEB server..."
    env HOME=/tmp s6-setuidgid $USER_ID:$GROUP_ID openssl req \
        -x509 \
        -nodes \
        -days 3650 \
        -newkey rsa:2048 \
        -subj "/C=CA/O=github.com\\/jlesage\\/$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')/OU=Docker container web access/CN=web.$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-').example.com" \
        -keyout "$CERT_DIR/web-privkey.pem" \
        -out "$CERT_DIR/web-fullchain.pem" \
        > /dev/null 2>&1
    chmod 400 "$CERT_DIR/web-privkey.pem"
fi

# Generate certificate used by the VNC server (stunnel).
if [ ! -f "$CERT_DIR/vnc-server.pem" ]; then
    log "Generating self-signed certificate for VNC server..."
    TMP_DIR="$(mktemp -d)"
    env HOME=/tmp openssl req \
        -x509 \
        -nodes \
        -days 3650 \
        -newkey rsa:2048 \
        -subj "/C=CA/O=github.com\\/jlesage\\/$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')/OU=Docker container VNC access/CN=vnc.$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-').example.com" \
        -keyout "$TMP_DIR/web-privkey.pem" \
        -out "$TMP_DIR/cert.pem" \
        > /dev/null 2>&1
    cat "$TMP_DIR/web-privkey.pem" \
        "$TMP_DIR/cert.pem" \
        "$CERT_DIR/dhparam.pem" > "$CERT_DIR/vnc-server.pem"
    chmod 400 "$CERT_DIR/vnc-server.pem"
    chown $USER_ID:$GROUP_ID "$CERT_DIR/vnc-server.pem"
    rm -r "$TMP_DIR"
fi

# vim: set ft=sh :
