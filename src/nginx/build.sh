#!/bin/sh
#
# Helper script that builds the TigerVNC server as a static binary.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Define software versions.
NGINX_VERSION=1.20.1
NGINXWEBSOCKIFYMOD_VERSION=0.0.3

# Define software download URLs.
NGINX_URL=http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
NGINXWEBSOCKIFYMOD_URL=https://github.com/tg123/websockify-nginx-module/archive/v${NGINXWEBSOCKIFYMOD_VERSION}.tar.gz

function log {
    echo ">>> $*"
}

#
# Install required packages.
#
log "Installing required Alpine packages..."
apk --no-cache add \
    build-base \
    curl \
    clang \

xx-apk --no-cache --no-scripts add \
    gcc \
    musl-dev \
    linux-headers \
    openssl-dev \
    openssl-libs-static \
    pcre-dev \

mkdir /tmp/nginx
log "Downloading Nginx..."
curl -# -L -f ${NGINX_URL} | tar -xz --strip 1 -C /tmp/nginx

log "Downloading WebSockify Nginx module..."
mkdir /tmp/websockify-nginx-module
curl -# -L -f ${NGINXWEBSOCKIFYMOD_URL} | tar xz --strip 1 -C /tmp/websockify-nginx-module

# See the Yocto Nginx recipe: https://github.com/openembedded/meta-openembedded/tree/master/meta-webserver/recipes-httpd/nginx
echo "Patching Nginx for cross-compile support..."
curl -# -L -f https://github.com/openembedded/meta-openembedded/raw/master/meta-webserver/recipes-httpd/nginx/files/nginx-cross.patch | patch -p1 -d /tmp/nginx
curl -# -L -f https://github.com/openembedded/meta-openembedded/raw/master/meta-webserver/recipes-httpd/nginx/files/0001-Allow-the-overriding-of-the-endianness-via-the-confi.patch | patch -p1 -d /tmp/nginx

case "$(xx-info arch)" in
    x86_64|aarch64) PTRSIZE=8 ;;
    *) PTRSIZE=4 ;;
esac

log "Configuring Nginx..."
(
    cd /tmp/nginx && ./configure \
        --crossbuild=Linux:$(xx-info arch) \
        --with-cc="xx-clang" \
        --with-cc-opt="-Os -fomit-frame-pointer -Wno-sign-compare" \
        --with-ld-opt="-Wl,--as-needed -static -Wl,--strip-all" \
        --prefix=/var/lib/nginx \
        --sbin-path=/sbin/nginx \
        --modules-path=/usr/lib/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --pid-path=/var/run/nginx/nginx.pid \
        --lock-path=/var/run/nginx/nginx.lock \
        --error-log-path=/config/log/nginx/error.log \
        --http-log-path=/config/log/nginx/access.log \
        \
        --with-int=4 \
        --with-long=${PTRSIZE} \
        --with-long-long=8 \
        --with-ptr-size=${PTRSIZE} \
        --with-sig-atomic-t=${PTRSIZE} \
        --with-size-t=${PTRSIZE} \
        --with-off-t=8 \
        --with-time-t=${PTRSIZE} \
        --with-sys-nerr=132 \
        \
        --http-client-body-temp-path=/var/tmp/nginx/client_body \
        --http-proxy-temp-path=/var/tmp/nginx/proxy \
        \
        --user=app \
        --group=app \
        \
        --with-threads \
        --with-file-aio \
        --with-http_ssl_module \
        --with-pcre \
        --with-pcre-jit \
        \
        --without-http_charset_module \
        --without-http_gzip_module \
        --without-http_ssi_module \
        --without-http_userid_module \
        --without-http_access_module \
        --without-http_auth_basic_module \
        --without-http_mirror_module \
        --without-http_autoindex_module \
        --without-http_geo_module \
        --without-http_split_clients_module \
        --without-http_referer_module \
        --without-http_rewrite_module \
        --without-http_fastcgi_module \
        --without-http_uwsgi_module \
        --without-http_scgi_module \
        --without-http_grpc_module \
        --without-http_memcached_module \
        --without-http_limit_conn_module \
        --without-http_limit_req_module \
        --without-http_empty_gif_module \
        --without-http_browser_module \
        --without-http_upstream_hash_module \
        --without-http_upstream_ip_hash_module \
        --without-http_upstream_least_conn_module \
        --without-http_upstream_keepalive_module \
        --without-http_upstream_zone_module \
        \
        --with-stream \
        --with-stream_ssl_module \
        \
        --add-module=/tmp/websockify-nginx-module \
)

log "Compiling Nginx..."
make -C /tmp/nginx -j$(nproc) && \

log "Installing Nginx..."
make DESTDIR=/tmp/nginx-install -C /tmp/nginx install
find /tmp/nginx-install/etc/nginx ! -name "mime.types" -type f -exec rm -v {} ';'
rm -r \
    /tmp/nginx-install/var \
    /tmp/nginx-install/config \

