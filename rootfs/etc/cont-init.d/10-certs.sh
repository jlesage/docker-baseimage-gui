#!/bin/sh
#
# Generate default certificate(s) when missing.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Exit now if secure connection not enabled.
is-bool-val-true "${SECURE_CONNECTION:-0}" || exit 0

CONTAINER_HOSTNAME="$(hostname)"
CERT_DIR=/config/certs
TMP_DIR="$(mktemp -d)"

mkdir -p "${CERT_DIR}"

get_openssl_cnf() {
    echo "
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[ req_distinguished_name ]
C = CA
CN = ${CONTAINER_HOSTNAME}
O = ${APP_NAME} Docker Container
OU = Self-signed certificate for $1

[ v3_req ]
subjectAltName = @alt_names
1.3.6.1.4.1.55555.1 = ASN1:UTF8String:container-generated

[ alt_names ]
DNS.1 = ${CONTAINER_HOSTNAME}
IP.1 = 127.0.0.1
IP.2 = ::1"
}

# Generate certificate used by the web server (nginx).
if [ ! -f "${CERT_DIR}"/web-privkey.pem ] && [ ! -f "${CERT_DIR}"/web-fullchain.pem ]; then
    echo "generating self-signed certificate for web server..."
    get_openssl_cnf "web access" > "${TMP_DIR}"/openssl-web.cnf
    env HOME="${TMP_DIR}" openssl req \
        -x509 \
        -nodes \
        -days 3650 \
        -newkey rsa:2048 \
        -keyout "${CERT_DIR}"/web-privkey.pem \
        -out "${CERT_DIR}"/web-fullchain.pem \
        -config "${TMP_DIR}"/openssl-web.cnf \
        > /dev/null 2>&1
    chmod 400 "${CERT_DIR}"/web-privkey.pem
fi

# If certificate from previous version is found, split it.
if [ -f "${CERT_DIR}"/vnc-server.pem ]; then
    echo "splitting ${CERT_DIR}/vnc-server.pem..."

    # Extract the private key.
    env HOME="${TMP_DIR}" openssl pkey \
        -in "${CERT_DIR}"/vnc-server.pem \
        -out "${CERT_DIR}"/vnc-privkey.pem
    chmod 400 "${CERT_DIR}"/vnc-privkey.pem

    # Extract certificates.
    env HOME="${TMP_DIR}" openssl crl2pkcs7 \
        -nocrl \
        -certfile "${CERT_DIR}"/vnc-server.pem \
        | env HOME="${TMP_DIR}" openssl pkcs7 \
            -print_certs \
            -out "${CERT_DIR}"/vnc-fullchain.pem

    mv "${CERT_DIR}"/vnc-server.pem "${CERT_DIR}"/vnc-server.pem.converted
fi

# Generate certificate used by the VNC server.
if [ ! -f "${CERT_DIR}"/vnc-privkey.pem ] && [ ! -f "${CERT_DIR}"/vnc-fullchain.pem ]; then
    echo "generating self-signed certificate for VNC server..."
    get_openssl_cnf "VNC access" > "${TMP_DIR}"/openssl-vnc.cnf
    env HOME="${TMP_DIR}" openssl req \
        -x509 \
        -nodes \
        -days 3650 \
        -newkey rsa:2048 \
        -keyout "${CERT_DIR}"/vnc-privkey.pem \
        -out "${CERT_DIR}"/vnc-fullchain.pem \
        -config "${TMP_DIR}"/openssl-vnc.cnf \
        > /dev/null 2>&1
    chmod 400 "${CERT_DIR}"/vnc-privkey.pem
fi

rm -rf "${TMP_DIR}"

[ -d /var/run/certsmonitor ] || mkdir --mode=755 /var/run/certsmonitor
chown "${USER_ID}:${GROUP_ID}" /var/run/certsmonitor

# vim:ft=sh:ts=4:sw=4:et:sts=4
