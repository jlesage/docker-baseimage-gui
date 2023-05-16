#!/bin/sh
#
# Helper script that builds the TigerVNC server as a static binary.
#
# This also builds a customized version of XKeyboard config files and the
# compiler (xkbcomp).  By using a different instance/version of XKeyboard, we
# prevent version mismatch issues thay could occur by using packages from the
# distro of the baseimage.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Define software versions.
TIGERVNC_VERSION=1.13.1
XSERVER_VERSION=1.20.14

# Use the same versions has Alpine 3.15.
GNUTLS_VERSION=3.7.1
LIBXFONT2_VERSION=2.0.5
LIBFONTENC_VERSION=1.1.4
LIBTASN1_VERSION=4.18.0
LIBXSHMFENCE_VERSION=1.3

# If the XKeyboardConfig version is too recent compared to xorgproto/libX11,
# xkbcomp will complain with warnings like "Could not resolve keysym ...".  With
# Alpine 3.15, XKeyboardConfig version 2.32 is the latest version that doesn't
# produces these warnings.
XKEYBOARDCONFIG_VERSION=2.32
XKBCOMP_VERSION=1.4.5

# Define software download URLs.
TIGERVNC_URL=https://github.com/TigerVNC/tigervnc/archive/v${TIGERVNC_VERSION}.tar.gz
XSERVER_URL=https://www.x.org/releases/individual/xserver/xorg-server-${XSERVER_VERSION}.tar.gz

GNUTLS_URL=https://www.gnupg.org/ftp/gcrypt/gnutls/v${GNUTLS_VERSION%.*}/gnutls-${GNUTLS_VERSION}.tar.xz
LIBXFONT2_URL=https://www.x.org/pub/individual/lib/libXfont2-${LIBXFONT2_VERSION}.tar.gz
LIBFONTENC_URL=https://www.x.org/releases/individual/lib/libfontenc-${LIBFONTENC_VERSION}.tar.gz
LIBTASN1_URL=https://ftp.gnu.org/gnu/libtasn1/libtasn1-${LIBTASN1_VERSION}.tar.gz
LIBXSHMFENCE_URL=https://www.x.org/releases/individual/lib/libxshmfence-${LIBXSHMFENCE_VERSION}.tar.gz

XKEYBOARDCONFIG_URL=https://www.x.org/archive/individual/data/xkeyboard-config/xkeyboard-config-${XKEYBOARDCONFIG_VERSION}.tar.bz2
XKBCOMP_URL=https://www.x.org/releases/individual/app/xkbcomp-${XKBCOMP_VERSION}.tar.bz2

# Set same default compilation flags as abuild.
export CFLAGS="-Os -fomit-frame-pointer"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS="-Wl,--as-needed --static -static -Wl,--strip-all"

export CC=xx-clang

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

function log {
    echo ">>> $*"
}

#
# Install required packages.
#
log "Installing required Alpine packages..."
apk --no-cache add \
    curl \
    build-base \
    clang \
    cmake \
    autoconf \
    automake \
    libtool \
    pkgconf \
    meson \
    util-macros \
    font-util-dev \
    xtrans \

xx-apk --no-cache --no-scripts add \
    g++ \
    xcb-util-dev \
    pixman-dev \
    libx11-dev \
    libgcrypt-dev \
    libgcrypt-static \
    libgpg-error-static \
    libxkbfile-dev \
    libxfont2-dev \
    libjpeg-turbo-dev \
    nettle-dev \
    libunistring-dev \
    gnutls-dev \
    fltk-dev \
    libxrandr-dev \
    libxtst-dev \
    freetype-dev \
    libfontenc-dev \
    zlib-dev \
    libx11-static \
    libxcb-static \
    zlib-static \
    pixman-static \
    libjpeg-turbo-static \
    freetype-static \
    libpng-static \
    bzip2-static \
    brotli-static \
    libunistring-static \
    nettle-static \
    gettext-static \
    libunistring-dev \
    libbsd-dev \

#
# Build GNU TLS.
# The static library is not provided by Alpine repository, so we need to build
# it ourself.
#
mkdir /tmp/gnutls
log "Downloading GNU TLS..."
curl -# -L -f ${GNUTLS_URL} | tar -xJ --strip 1 -C /tmp/gnutls
log "Configuring GNU TLS..."
(
    cd /tmp/gnutls && ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
        --disable-openssl-compatibility \
        --disable-rpath \
        --disable-guile \
        --disable-valgrind-tests \
        --disable-cxx \
        --without-p11-kit \
        --disable-tools \
        --disable-doc \
        --enable-static \
        --disable-shared \
)
log "Compiling GNU TLS..."
make -C /tmp/gnutls -j$(nproc)
log "Installing GNU TLS..."
make DESTDIR=$(xx-info sysroot) -C /tmp/gnutls install

#
# Build libXfont2
# The static library is not provided by Alpine repository, so we need to build
# it ourself.
#
mkdir /tmp/libxfont2
log "Downloading libXfont2..."
curl -# -L -f ${LIBXFONT2_URL} | tar -xz --strip 1 -C /tmp/libxfont2
log "Configuring libXfont2..."
(
    cd /tmp/libxfont2 && ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
        --without-fop \
        --without-xmlto \
        --disable-devel-docs \
        --enable-static \
        --disable-shared \
)
log "Compiling libXfont2..."
sed 's/^noinst_PROGRAMS = /#noinst_PROGRAMS = /' -i /tmp/libxfont2/Makefile.in
make -C /tmp/libxfont2 -j$(nproc)
log "Installing libXfont2..."
make DESTDIR=$(xx-info sysroot) -C /tmp/libxfont2 install

#
# Build libfontenc
# The static library is not provided by Alpine repository, so we need to build
# it ourself.
#
mkdir /tmp/libfontenc
log "Downloading libfontenc..."
curl -# -L -f ${LIBFONTENC_URL} | tar -xz --strip 1 -C /tmp/libfontenc
log "Configuring libfontenc..."
(
    cd /tmp/libfontenc && ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
        --with-encodingsdir=/usr/share/fonts/encodings \
        --enable-static \
        --disable-shared \
)
log "Compiling libfontenc..."
make -C /tmp/libfontenc -j$(nproc)
log "Installing libfontenc..."
make DESTDIR=$(xx-info sysroot) -C /tmp/libfontenc install

#
# Build libtasn1
# The static library is not provided by Alpine repository, so we need to build
# it ourself.
#
mkdir /tmp/libtasn1
log "Downloading libtasn1..."
curl -# -L -f ${LIBTASN1_URL} | tar -xz --strip 1 -C /tmp/libtasn1
log "Configuring libtasn1..."
(
    cd /tmp/libtasn1 && CFLAGS="$CFLAGS -Wno-error=inline" ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
        --enable-static \
        --disable-shared \
)
log "Compiling libtasn1..."
make -C /tmp/libtasn1 -j$(nproc)
log "Installing libtasn1..."
make DESTDIR=$(xx-info sysroot) -C /tmp/libtasn1 install

#
# Build libxshmfence
# The static library is not provided by Alpine repository, so we need to build
# it ourself.
#
mkdir /tmp/libxshmfence
log "Downloading libxshmfence..."
curl -# -L -f ${LIBXSHMFENCE_URL} | tar -xz --strip 1 -C /tmp/libxshmfence
log "Configuring libxshmfence..."
(
    cd /tmp/libxshmfence && ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
        --enable-static \
        --disable-shared \
        --enable-futex \
)
log "Compiling libxshmfence..."
make -C /tmp/libxshmfence -j$(nproc)
log "Installing libxshmfence..."
make DESTDIR=$(xx-info sysroot) -C /tmp/libxshmfence install

#
# Build TigerVNC
#
mkdir /tmp/tigervnc
log "Downloading TigerVNC..."
curl -# -L -f ${TIGERVNC_URL} | tar -xz --strip 1 -C /tmp/tigervnc
log "Downloading Xorg server..."
curl -# -L -f ${XSERVER_URL} | tar -xz --strip 1 -C /tmp/tigervnc/unix/xserver

log "Patching TigerVNC..."
# Apply the TigerVNC patch against the X server.
patch -p1 -d /tmp/tigervnc/unix/xserver < /tmp/tigervnc/unix/xserver120.patch
# Build a static binary of vncpasswd.
patch -p1 -d /tmp/tigervnc < "$SCRIPT_DIR"/vncpasswd-static.patch
# Disable PAM support.
patch -p1 -d /tmp/tigervnc < "$SCRIPT_DIR"/disable-pam.patch
# Fix static build.
patch -p1 -d /tmp/tigervnc < "$SCRIPT_DIR"/static-build.patch

log "Configuring TigerVNC..."
(
    cd /tmp/tigervnc && cmake -G "Unix Makefiles" \
        $(xx-clang --print-cmake-defines) \
        -DCMAKE_FIND_ROOT_PATH=$(xx-info sysroot) \
        -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DINSTALL_SYSTEMD_UNITS=OFF \
        -DENABLE_NLS=OFF \
        -DENABLE_GNUTLS=ON \
        -DENABLE_NETTLE=ON \
        -DBUILD_VIEWER=OFF \
)

log "Compiling TigerVNC common libraries and tools..."
make -C /tmp/tigervnc/common -j$(nproc)
make -C /tmp/tigervnc/unix/common -j$(nproc)
make -C /tmp/tigervnc/unix/vncpasswd -j$(nproc)

log "Configuring TigerVNC server..."
autoreconf -fiv /tmp/tigervnc/unix/xserver
(
    cd /tmp/tigervnc/unix/xserver && CFLAGS="$CFLAGS -Wno-implicit-function-declaration" ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
        --sysconfdir=/etc/X11 \
        --localstatedir=/var \
        --with-xkb-path=/opt/base/share/X11/xkb \
        --with-xkb-output=/var/lib/xkb \
        --with-xkb-bin-directory=/opt/base/bin \
        --with-default-font-path=/usr/share/fonts/misc,/usr/share/fonts/100dpi:unscaled,/usr/share/fonts/75dpi:unscaled,/usr/share/fonts/TTF,/usr/share/fonts/Type1 \
        --disable-docs \
        --disable-unit-tests \
        --without-dtrace \
        \
        --with-pic \
        --disable-static \
        --disable-shared \
        \
        --disable-listen-tcp \
        --enable-listen-unix \
        --disable-listen-local \
        \
        --disable-dpms \
        \
        --disable-systemd-logind \
        --disable-config-hal \
        --disable-config-udev \
        --disable-xorg \
        --disable-dmx \
        --disable-libdrm \
        --disable-dri \
        --disable-dri2 \
        --disable-dri3 \
        --disable-present \
        --disable-xvfb \
        --disable-glx \
        --disable-xinerama \
        --disable-record \
        --disable-xf86vidmode \
        --disable-xnest \
        --disable-xquartz \
        --disable-xwayland \
        --disable-xwayland-eglstream \
        --disable-standalone-xpbproxy \
        --disable-xwin \
        --disable-glamor \
        --disable-kdrive \
        --disable-xephyr \
)

# Remove all automatic dependencies on libraries and manually define them to
# have the correct order.
find /tmp/tigervnc -name "*.la" -exec sed 's/^dependency_libs/#dependency_libs/' -i {} ';'
sed 's/^XSERVER_SYS_LIBS = .*/XSERVER_SYS_LIBS = -lXau -lXdmcp -lpixman-1 -ljpeg -lXfont2 -lfreetype -lfontenc -lpng16 -lbrotlidec -lbrotlicommon -lz -lbz2 -lgnutls -lhogweed -lgmp -lnettle -lunistring -ltasn1 -lbsd -lmd/' -i /tmp/tigervnc/unix/xserver/hw/vnc/Makefile

log "Compiling TigerVNC server..."
make -C /tmp/tigervnc/unix/xserver -j$(nproc)

log "Installing TigerVNC server..."
make DESTDIR=/tmp/tigervnc-install -C /tmp/tigervnc/unix/xserver install

log "Installing TigerVNC vncpasswd tool..."
make DESTDIR=/tmp/tigervnc-install -C /tmp/tigervnc/unix/vncpasswd install

#
# Build XKeyboardConfig.
#
mkdir /tmp/xkb
log "Downloading XKeyboardConfig..."
curl -# -L -f ${XKEYBOARDCONFIG_URL} | tar -xj --strip 1 -C /tmp/xkb
log "Configuring XKeyboardConfig..."
(
    cd /tmp/xkb && abuild-meson . build
)
log "Compiling XKeyboardConfig..."
meson compile -C /tmp/xkb/build
log "Installing XKeyboardConfig..."
DESTDIR="/tmp/xkb-install" meson install --no-rebuild -C /tmp/xkb/build

log "Stripping XKeyboardConfig..."
# We keep only the files needed by Xvnc.
TO_KEEP="
    geometry/pc
    symbols/pc
    symbols/us
    symbols/srvr_ctrl
    symbols/keypad
    symbols/altwin
    symbols/inet
    compat/accessx
    compat/basic
    compat/caps
    compat/complete
    compat/iso9995
    compat/ledcaps
    compat/lednum
    compat/ledscroll
    compat/level5
    compat/misc
    compat/mousekeys
    compat/xfree86
    keycodes/evdev
    keycodes/aliases
    types/basic
    types/complete
    types/extra
    types/iso9995
    types/level5
    types/mousekeys
    types/numpad
    types/pc
    rules/evdev
"
find /tmp/xkb-install/usr/share/X11/xkb -mindepth 2 -maxdepth 2 -type d -print -exec rm -r {} ';'
find /tmp/xkb-install/usr/share/X11/xkb -mindepth 1 ! -type d $(printf "! -wholename /tmp/xkb-install/usr/share/X11/xkb/%s " $(echo "$TO_KEEP")) -print -delete

#
# Build xkbcomp.
#
mkdir /tmp/xkbcomp
log "Downloading xkbcomp..."
curl -# -L -f ${XKBCOMP_URL} | tar -xj --strip 1 -C /tmp/xkbcomp

log "Configuring xkbcomp..."
(
    LDFLAGS="-Wl,--as-needed --static -static -Wl,--strip-all -Wl,--start-group -lX11 -lxcb -lXdmcp -lXau -Wl,--end-group" && \
    cd /tmp/xkbcomp && \
    LDFLAGS="-Wl,--as-needed --static -static -Wl,--strip-all -Wl,--start-group -lX11 -lxcb -lXdmcp -lXau -Wl,--end-group" LIBS="$LDFLAGS" ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
)

log "Compiling xkbcomp..."
make -C /tmp/xkbcomp -j$(nproc)

log "Installing xkbcomp..."
make DESTDIR=/tmp/xkbcomp-install -C /tmp/xkbcomp install

