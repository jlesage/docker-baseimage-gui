#!/bin/sh
#
# Helper script that builds htpasswd tool as a static binary.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Define software versions.
HTTPD_VERSION=2.4.63

# Define software download URLs.
HTTPD_URL=https://dlcdn.apache.org/httpd/httpd-${HTTPD_VERSION}.tar.gz

# Set same default compilation flags as abuild.
export CFLAGS="-Os -fomit-frame-pointer"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS="-Wl,--as-needed,-O1,--sort-common --static -static -Wl,--strip-all"

export CC=xx-clang
export CXX=xx-clang++

function log {
    echo ">>> $*"
}

#
# Install required packages.
#
HOST_PKGS="\
    curl \
    build-base \
    clang \
"

TARGET_PKGS="\
    g++ \
    apr-dev \
    apr-util-dev \
    pcre2-dev \
    expat-static \
    util-linux-static \
"

log "Installing required Alpine packages..."
apk --no-cache add $HOST_PKGS
xx-apk --no-cache --no-scripts add $TARGET_PKGS

#
# Build httpd.
#
mkdir /tmp/httpd
log "Downloading httpd..."
curl -# -L -f ${HTTPD_URL} | tar -xz --strip 1 -C /tmp/httpd

log "Configuring httpd..."
(
    cd /tmp/httpd && PCRE_CONFIG=$(xx-info sysroot)usr/bin/pcre2-config ap_cv_void_ptr_lt_long=no ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --with-apr=$(xx-info sysroot)usr \
        --with-apr-util=$(xx-info sysroot)usr \
        --enable-static-htpasswd \
)

# Fix paths to use for cross-compilation.
sed -i "s|-L/usr/lib|-L$(xx-info sysroot)usr/lib|" /tmp/httpd/build/config_vars.mk
sed -i "s|-R/usr/lib|-R$(xx-info sysroot)usr/lib|" /tmp/httpd/build/config_vars.mk

log "Compiling httpd..."
make -C /tmp/httpd/support -j$(nproc) htpasswd

log "Installing httpd..."
mkdir -p /tmp/httpd-install/usr/bin
cp -v /tmp/httpd/support/htpasswd /tmp/httpd-install/usr/bin/

#
# Cleanup.
#
log "Performing cleanup..."
apk --no-cache del $HOST_PKGS
xx-apk --no-cache --no-scripts del $TARGET_PKGS
apk --no-cache add util-linux # Linux tools still needed and they might be removed if pulled by dependencies.
rm -rf /tmp/httpd
