#!/bin/sh
#
# Helper script that builds PulseAudio as a static binary.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Define software versions.
PULSEAUDIO_VERSION=16.1
LIBSNDFILE_VERSION=1.2.2

# Define software download URLs.
PULSEAUDIO_URL=https://www.freedesktop.org/software/pulseaudio/releases/pulseaudio-${PULSEAUDIO_VERSION}.tar.xz
LIBSNDFILE_URL=https://github.com/libsndfile/libsndfile/releases/download/${LIBSNDFILE_VERSION}/libsndfile-${LIBSNDFILE_VERSION}.tar.xz

# Set same default compilation flags as abuild.
export CFLAGS="-Os -fomit-frame-pointer -ffunction-sections -fdata-sections"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS="-Wl,--gc-sections"

export CC=xx-clang
export CXX=xx-clang++

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

function log {
    echo ">>> $*"
}

#
# Install required packages.
#
HOST_PKGS="\
    curl \
    build-base \
    abuild \
    clang \
    meson \
    m4 \
    pkgconfig \
    glib-dev \
"

TARGET_PKGS="\
    g++ \
    glib-dev \
    glib-static \
    libtool \
    libcap-dev \
    libcap-static \
"

log "Installing required Alpine packages..."
apk --no-cache add $HOST_PKGS
xx-apk --no-cache --no-scripts add $TARGET_PKGS

#
# Build libsndfile
#
mkdir /tmp/libsndfile
log "Downloading libsndfile..."
curl -# -L -f ${LIBSNDFILE_URL} | tar -xJ --strip 1 -C /tmp/libsndfile

log "Configuring libsndfile..."
(
    cd /tmp/libsndfile && LDFLAGS= ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
        --enable-static \
        --disable-shared \
        --disable-sqlite \
        --disable-external-libs \
        --disable-mpeg \
        --disable-full-suite \
)

log "Compiling libsndfile..."
make -C /tmp/libsndfile -j$(nproc)

log "Installing libsndfile..."
DESTDIR=$(xx-info sysroot) make -C /tmp/libsndfile install

#
# Build PulseAudio.
#
mkdir /tmp/pulseaudio
log "Downloading PulseAudio..."
curl -# -L -f ${PULSEAUDIO_URL} | tar -xJ --strip 1 -C /tmp/pulseaudio

log "Patching PulseAudio..."
patch -p1 -d /tmp/pulseaudio < "$SCRIPT_DIR"/meson-build.patch
patch -p1 -d /tmp/pulseaudio < "$SCRIPT_DIR"/static-modules.patch
patch -p1 -d /tmp/pulseaudio < "$SCRIPT_DIR"/daemon.patch
cp -v "$SCRIPT_DIR"/ltdl-static.c /tmp/pulseaudio/src/pulsecore/

log "Configuring PulseAudio..."
echo "[binaries]
pkgconfig = '$(xx-info)-pkg-config'
strip = '$(xx-info)-strip'

[properties]
sys_root = '$(xx-info sysroot)'
pkg_config_libdir = '$(xx-info sysroot)/usr/lib/pkgconfig'

[host_machine]
system = 'linux'
cpu_family = '$(xx-info arch)'
cpu = '$(xx-info arch)'
endian = 'little'
" > /tmp/pulseaudio/meson-cross.txt
(
    cd /tmp/pulseaudio && abuild-meson \
        -Ddaemon=true \
        -Dclient=true \
        -Ddoxygen=false \
        -Dgcov=false \
        -Dman=false \
        -Dtests=false \
        -Ddatabase=simple \
        -Dmodlibexecdir=/opt/base/lib/pulseaudio/modules \
        -Dalsa=disabled \
        -Dasyncns=disabled \
        -Davahi=disabled \
        -Dbluez5=disabled \
        -Dbluez5-gstreamer=disabled \
        -Dbluez5-native-headset=false \
        -Dbluez5-ofono-headset=false \
        -Ddbus=disabled \
        -Delogind=disabled \
        -Dfftw=disabled \
        -Dgsettings=disabled \
        -Dgstreamer=disabled \
        -Dgtk=disabled \
        -Dhal-compat=false \
        -Dipv6=false \
        -Djack=disabled \
        -Dlirc=disabled \
        -Dopenssl=disabled \
        -Dorc=disabled \
        -Doss-output=disabled \
        -Dsoxr=disabled \
        -Dspeex=disabled \
        -Dsystemd=disabled \
        -Dtcpwrap=disabled \
        -Dudev=disabled \
        -Dvalgrind=disabled \
        -Dx11=disabled \
        -Dadrian-aec=true \
        -Dwebrtc-aec=disabled \
        --buildtype release \
        --default-library static \
        --cross-file /tmp/pulseaudio/meson-cross.txt \
        build \
)

# Compilation of ARM neon asm fails.
sed -i '/HAVE_NEON/d' /tmp/pulseaudio/build/config.h

log "Compiling PulseAudio..."
make -f "$SCRIPT_DIR"/Makefile -C /tmp/pulseaudio -j$(nproc)

log "Installing PulseAudio..."
mkdir -p /tmp/pulseaudio-install/usr/bin
cp -v /tmp/pulseaudio/pulseaudio /tmp/pulseaudio-install/usr/bin/

#
# Cleanup.
#
log "Performing cleanup..."
apk --no-cache del $HOST_PKGS
xx-apk --no-cache --no-scripts del $TARGET_PKGS
apk --no-cache add util-linux # Linux tools still needed and they might be removed if pulled by dependencies.
rm -rf /tmp/pulseaudio
