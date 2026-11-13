#!/bin/sh
#
# Helper script that builds Fontconfig as a static library.
#
# A customized fontconfig library is used.  This is required to allows baseimage
# programs (like openbox and yad) to use independant fonts and font configuration
# files.  This way, these programs don't depend on distro of the baseimage.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Define software versions.
FONTCONFIG_VERSION=2.15.0

# Define software download URLs.
FONTCONFIG_URL=https://www.freedesktop.org/software/fontconfig/release/fontconfig-${FONTCONFIG_VERSION}.tar.gz

# Set same default compilation flags as abuild.
export CFLAGS="-Os -fomit-frame-pointer"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS="-Wl,--strip-all -Wl,--as-needed,-O1,--sort-common"

export CC=xx-clang
export CXX=xx-clang++

log() {
    echo ">>> $*"
}

#
# Install required packages.
#

QEMU_PKG=
if xx-info is-cross; then
    case "$(xx-info march)" in
        x86_64) QEMU_PKG=qemu-x86_64 ;;
        i386) QEMU_PKG=qemu-i386 ;;
        aarch64) QEMU_PKG=qemu-aarch64 ;;
        armv6l|armv7l) QEMU_PKG=qemu-arm ;;
        *)
            echo "ERROR: no QEMU user emulator for $(xx-info march)."
            exit 1
            ;;
    esac
    QEMU_BIN="${QEMU_PKG}"
fi

HOST_PKGS="\
    curl \
    build-base \
    clang \
    pkgconfig \
    gperf \
    python3 \
    font-croscore \
    $QEMU_PKG
"

TARGET_PKGS="\
    glib-dev \
    g++ \
    freetype-dev \
    expat-dev \
"

log "Installing required Alpine packages..."
apk --no-cache add $HOST_PKGS
xx-apk --no-cache --no-scripts add $TARGET_PKGS

#
# Install Noto fonts.
# Only the fonts used by Openbox are installed.
#
log "Installing Noto fonts..."
mkdir -p /tmp/fontconfig-install/opt/base/share/fonts
for FONT in Arimo-Regular Arimo-Bold
do
    cp -v /usr/share/fonts/croscore/$FONT.ttf /tmp/fontconfig-install/opt/base/share/fonts/
done

#
# Build fontconfig.
# The static library will be used by some baseimage programs.  We need to
# compile our own version to adjust different paths used by fontconfig.
# The fc-cache output is architecture dependent, so it is generated below
# for this target and shipped under /opt.  Container startup copies it into
# the writable cache directory.
#
mkdir /tmp/fontconfig
log "Downloading fontconfig..."
curl -# -L -f ${FONTCONFIG_URL} | tar -xz --strip 1 -C /tmp/fontconfig

log "Configuring fontconfig..."
(
    cd /tmp/fontconfig && ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
        --with-default-fonts=/opt/base/share/fonts \
        --with-baseconfigdir=/opt/base/share/fontconfig \
        --with-configdir=/opt/base/share/fontconfig/conf.d \
        --with-templatedir=/opt/base/share/fontconfig/conf.avail \
        --with-cache-dir=/config/xdg/cache/fontconfig \
        --disable-shared \
        --enable-static \
        --disable-docs \
        --disable-nls \
        --disable-cache-build \
)

log "Compiling fontconfig..."
make -C /tmp/fontconfig -j$(nproc)

log "Installing fontconfig..."
make DESTDIR=/tmp/fontconfig-install -C /tmp/fontconfig install

#
# Generate the fontconfig cache for this target architecture.
#
# The cache checksum is the font directory's mtime, including nanoseconds.
# Pin that timestamp before fc-cache runs, and do not touch the directory
# afterwards, so the checksum still matches after the directory is copied
# into the image.
#
# fc-cache is a target binary. Its compiled-in paths are the paths used in
# the container, so the fonts and configuration are exposed at those paths
# for the run. QEMU's -L prefix is only the ELF interpreter prefix: file
# lookups still use the paths below.
#
log "Generating fontconfig cache..."
touch -d '2020-01-01 00:00:00' /tmp/fontconfig-install/opt/base/share/fonts/*.ttf
touch -d '2020-01-01 00:00:00' /tmp/fontconfig-install/opt/base/share/fonts
FONT_DIR_TIME="$(stat -c '%y' /tmp/fontconfig-install/opt/base/share/fonts)"

(
    export HOME=/tmp/fc-home
    export XDG_CACHE_HOME=/config/xdg/cache
    unset SOURCE_DATE_EPOCH

    rm -rf /opt/base /config /tmp/fc-home
    mkdir -p /opt/base /config/xdg/cache/fontconfig /tmp/fc-home
    cp -a /tmp/fontconfig-install/opt/base/share /opt/base/share

    if xx-info is-cross; then
        "$QEMU_BIN" -L "$(xx-info sysroot)" \
            /tmp/fontconfig-install/usr/bin/fc-cache -f -s -v
    else
        /tmp/fontconfig-install/usr/bin/fc-cache -f -s -v
    fi

    mkdir -p /tmp/fontconfig-install/opt/base/share/fontconfig/cache
    cp -av /config/xdg/cache/fontconfig/*.cache-* \
        /tmp/fontconfig-install/opt/base/share/fontconfig/cache/
    rm -rf /opt/base /config /tmp/fc-home
)

if [ "$(stat -c '%y' /tmp/fontconfig-install/opt/base/share/fonts)" != "$FONT_DIR_TIME" ]; then
    echo "ERROR: font directory timestamp changed while generating the cache."
    exit 1
fi

#
# Cleanup.
#
log "Performing cleanup..."
apk --no-cache del $HOST_PKGS
xx-apk --no-cache --no-scripts del $TARGET_PKGS
apk --no-cache add util-linux # Linux tools still needed and they might be removed if pulled by dependencies.
rm -rf /tmp/fontconfig
