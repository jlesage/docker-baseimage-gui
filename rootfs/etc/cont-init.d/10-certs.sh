#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Exit now if secure connection not enabled.
is-bool-val-true "${SECURE_CONNECTION:-0}" || exit 0

CERT_DIR=/config/certs
TMP_DIR="$(mktemp -d)"

mkdir -p "$CERT_DIR"

# Generate DH parameters.
if [ ! -f "$CERT_DIR/dhparam.pem" ]; then
    echo "generating DH parameters (2048 bits), this is going to take a long time..."
    env HOME="$TMP_DIR" openssl dhparam \
        -out "$CERT_DIR/dhparam.pem" \
        2048 \
        > /dev/null 2>&1
fi

# Generate certificate used by the WEB server (nginx).
if [ ! -f "$CERT_DIR/web-privkey.pem" ] && [ ! -f "$CERT_DIR/web-fullchain.pem" ]; then
    echo "generating self-signed certificate for WEB server..."
    env HOME="$TMP_DIR" openssl req \
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

# If certificate from previous version is found, split it.
if [ -f "$CERT_DIR/vnc-server.pem" ]; then
    echo "splitting $CERT_DIR/vnc-server.pem..."

    # Extract the private key.
    env HOME="$TMP_DIR" openssl pkey \
        -in "$CERT_DIR/vnc-server.pem" \
        -out "$CERT_DIR/vnc-privkey.pem"
    chmod 400 "$CERT_DIR/vnc-privkey.pem"

    # Extract certificates.
    env HOME="$TMP_DIR" openssl crl2pkcs7 \
        -nocrl \
        -certfile "$CERT_DIR/vnc-server.pem" \
        | \
    env HOME="$TMP_DIR" openssl pkcs7 \
        -print_certs \
        -out "$CERT_DIR/vnc-fullchain.pem"

    mv "$CERT_DIR/vnc-server.pem"  "$CERT_DIR/vnc-server.pem.converted"
fi

# Generate certificate used by the VNC server.
if [ ! -f "$CERT_DIR/vnc-privkey.pem" ] && [ ! -f "$CERT_DIR/vnc-fullchain.pem" ] ; then
    echo "generating self-signed certificate for VNC server..."
    env HOME="$TMP_DIR" openssl req \
        -x509 \
        -nodes \
        -days 3650 \
        -newkey rsa:2048 \
        -subj "/C=CA/O=github.com\\/jlesage\\/$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')/OU=Docker container VNC access/CN=vnc.$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-').example.com" \
        -keyout "$CERT_DIR/vnc-privkey.pem" \
        -out "$CERT_DIR/vnc-fullchain.pem" \
        > /dev/null 2>&1
    chmod 400 "$CERT_DIR/vnc-privkey.pem"
fi

rm -rf "$TMP_DIR"

mkdir -p /var/run/certsmonitor
chown "$USER_ID:$GROUP_ID" /var/run/certsmonitor

# vim:ft=sh:ts=4:sw=4:et:sts=4
