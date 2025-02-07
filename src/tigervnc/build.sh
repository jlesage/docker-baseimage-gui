#!/bin/sh
#
# Helper script that builds the TigerVNC server as a static binary.
#
# This also builds a customized version of XKeyboard config files and the
# compiler (xkbcomp).  By using a different instance/version of XKeyboard, we
# prevent version mismatch issues that could occur by using packages from the
# distro of the baseimage.
#
# NOTE: This script is expected to be run under Alpine Linux.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Define software versions.
TIGERVNC_VERSION=1.14.1
XSERVER_VERSION=1.20.14

# Use the same versions has Alpine 3.20.
GMP_VERSION=6.3.0
GNUTLS_VERSION=3.8.5
LIBXFONT2_VERSION=2.0.6
LIBFONTENC_VERSION=1.1.8
LIBTASN1_VERSION=4.19.0
LIBXSHMFENCE_VERSION=1.3.2
# If the XKeyboardConfig version is too recent compared to xorgproto/libX11,
# xkbcomp will complain with warnings like "Could not resolve keysym ...".
XKEYBOARDCONFIG_VERSION=2.41
XKBCOMP_VERSION=1.4.7
PIXMAN_VERSION=0.43.4
BROTLI_VERSION=1.1.0
MESA_VERSION=24.0.8

# Define software download URLs.
TIGERVNC_URL=https://github.com/TigerVNC/tigervnc/archive/v${TIGERVNC_VERSION}.tar.gz
XSERVER_URL=https://www.x.org/releases/individual/xserver/xorg-server-${XSERVER_VERSION}.tar.gz

GMP_URL=https://ftp.gnu.org/gnu/gmp/gmp-${GMP_VERSION}.tar.xz
GNUTLS_URL=https://www.gnupg.org/ftp/gcrypt/gnutls/v${GNUTLS_VERSION%.*}/gnutls-${GNUTLS_VERSION}.tar.xz
LIBXFONT2_URL=https://www.x.org/pub/individual/lib/libXfont2-${LIBXFONT2_VERSION}.tar.gz
LIBFONTENC_URL=https://www.x.org/releases/individual/lib/libfontenc-${LIBFONTENC_VERSION}.tar.gz
LIBTASN1_URL=https://ftp.gnu.org/gnu/libtasn1/libtasn1-${LIBTASN1_VERSION}.tar.gz
LIBXSHMFENCE_URL=https://www.x.org/releases/individual/lib/libxshmfence-${LIBXSHMFENCE_VERSION}.tar.gz
PIXMAN_URL=https://www.x.org/releases/individual/lib/pixman-${PIXMAN_VERSION}.tar.xz
BROTLI_URL=https://github.com/google/brotli/archive/refs/tags/v${BROTLI_VERSION}.tar.gz
MESA_URL=https://mesa.freedesktop.org/archive/mesa-${MESA_VERSION}.tar.xz

XKEYBOARDCONFIG_URL=https://www.x.org/archive/individual/data/xkeyboard-config/xkeyboard-config-${XKEYBOARDCONFIG_VERSION}.tar.xz
XKBCOMP_URL=https://www.x.org/releases/individual/app/xkbcomp-${XKBCOMP_VERSION}.tar.xz

# Set same default compilation flags as abuild.
export CFLAGS="-Os -fomit-frame-pointer"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS="-fuse-ld=lld -Wl,--as-needed,-O1,--sort-common --static -static -Wl,--strip-all"

export CC=xx-clang
export CXX=xx-clang++

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

function log {
    echo ">>> $*"
}

function to_cmake_cpu_family() {
    _arch="$1"
    case "$(xx-info march)" in
        amd64|x86_64)
            _arch="x86_64"
            ;;
        386|i386)
            _arch="x86";
            ;;
        arm64|aarch64)
            _arch="aarch64";
            ;;
        arm|armv7l|armv6l)
            _arch="arm";
            ;;
        *)
            echo "ERROR: Unknown arch '$_arch'."
            exit 1
            ;;
    esac
    echo "$_arch"
}

#
# Install required packages.
#
HOST_PKGS="\
    curl \
    build-base \
    abuild \
    clang \
    lld \
    cmake \
    autoconf \
    automake \
    libtool \
    pkgconf \
    meson \
    util-macros \
    font-util-dev \
    xtrans \
    xz \
"

TARGET_PKGS="\
    g++ \
    xcb-util-dev \
    libx11-dev \
    libgcrypt-dev \
    libgcrypt-static \
    libgpg-error-static \
    libxkbfile-dev \
    libjpeg-turbo-dev \
    nettle-dev \
    libunistring-dev \
    fltk-dev \
    libxrandr-dev \
    libxtst-dev \
    freetype-dev \
    libfontenc-dev \
    zlib-dev \
    libx11-static \
    libxcb-static \
    zlib-static \
    libjpeg-turbo-static \
    freetype-static \
    libpng-static \
    bzip2-static \
    libunistring-static \
    nettle-static \
    gettext-static \
    libunistring-dev \
    libbsd-dev \
    libbsd-static \
    libidn2-static \
"

log "Installing required Alpine packages..."
apk --no-cache add $HOST_PKGS
xx-apk --no-cache --no-scripts add $TARGET_PKGS

echo "[binaries]
pkgconfig = '$(xx-info)-pkg-config'

[properties]
sys_root = '$(xx-info sysroot)'
pkg_config_libdir = '$(xx-info sysroot)/usr/lib/pkgconfig'

[host_machine]
system = 'linux'
cpu_family = '$(to_cmake_cpu_family "$(xx-info arch)")'
cpu = '$(to_cmake_cpu_family "$(xx-info arch)")'
endian = 'little'
" > /tmp/meson-cross.txt

#
# Build GMP.
# The library in Alpine repository is built with LTO, which causes static
# linking issue, so we need to build it ourself.
#
mkdir /tmp/gmp
log "Downloading GMP..."
curl -# -L -f ${GMP_URL} | tar -xJ --strip 1 -C /tmp/gmp
log "Configuring GMP..."
(
    cd /tmp/gmp && ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
        --with-pic \
        --enable-static \
        --disable-shared \
)
log "Compiling GMP..."
make -C /tmp/gmp -j$(nproc)
log "Installing GMP..."
make DESTDIR=$(xx-info sysroot) -C /tmp/gmp install
find $(xx-info sysroot)usr/lib -name "*.la" -delete

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
find $(xx-info sysroot)usr/lib -name "*.la" -delete

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
find $(xx-info sysroot)usr/lib -name "*.la" -delete

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
find $(xx-info sysroot)usr/lib -name "*.la" -delete

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
find $(xx-info sysroot)usr/lib -name "*.la" -delete

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
find $(xx-info sysroot)usr/lib -name "*.la" -delete

#
# Build pixman.
# The library in Alpine repository is built with LTO, which causes static
# linking issue, so we need to build it ourself.
#
mkdir /tmp/pixman
log "Downloading pixman..."
curl -# -L -f ${PIXMAN_URL} | tar -xJ --strip 1 -C /tmp/pixman
log "Configuring pixman..."
(
    cd /tmp/pixman && \
    LDFLAGS="$LDFLAGS -Wl,-z,stack-size=2097152" \
    abuild-meson \
        -Db_lto=false \
        -Ddefault_library=static \
        -Dtests=disabled \
        -Ddemos=disabled \
        --cross-file /tmp/meson-cross.txt \
        . build
)
log "Compiling pixman..."
meson compile -C /tmp/pixman/build
log "Installing pixman..."
DESTDIR=$(xx-info sysroot) meson install --no-rebuild -C /tmp/pixman/build
find $(xx-info sysroot)usr/lib -name "*.la" -delete

#
# Build brotli.
# The library in Alpine repository is built with LTO, which causes static
# linking issue, so we need to build it ourself.
#
mkdir /tmp/brotli
log "Downloading brotli..."
curl -# -L -f ${BROTLI_URL} | tar -xz --strip 1 -C /tmp/brotli
log "Configuring brotli..."
(
    mkdir /tmp/brotli/build && \
    cd /tmp/brotli/build && cmake \
        $(xx-clang --print-cmake-defines) \
        -DCMAKE_FIND_ROOT_PATH=$(xx-info sysroot) \
        -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=None \
	-DBUILD_SHARED_LIBS=OFF \
        ..
)
log "Compiling brotli..."
make -C /tmp/brotli/build -j$(nproc)
log "Installing brotli..."
make DESTDIR=$(xx-info sysroot) -C /tmp/brotli/build install
find $(xx-info sysroot)usr/lib -name "*.la" -delete

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
# Support for internal connection security types.
patch -p1 -d /tmp/tigervnc < "$SCRIPT_DIR"/internal-conn-sec-types.patch

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
    cd /tmp/tigervnc/unix/xserver && \
        CFLAGS="$CFLAGS -Wno-implicit-function-declaration" \
        LIBS="-ltasn1 -lunistring -lfreetype -lfontenc -lpng16 -lbrotlidec -lbrotlicommon -lbz2 -lintl" \
        ./configure \
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
        --enable-present \
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

log "Compiling TigerVNC server..."
make V=0 -C /tmp/tigervnc/unix/xserver -j$(nproc)

log "Installing TigerVNC server..."
make DESTDIR=/tmp/tigervnc-install -C /tmp/tigervnc/unix/xserver install

log "Installing TigerVNC vncpasswd tool..."
make DESTDIR=/tmp/tigervnc-install -C /tmp/tigervnc/unix/vncpasswd install

#
# Cleanup.
#
log "Performing cleanup..."
apk --no-cache del $HOST_PKGS
xx-apk --no-cache --no-scripts del $TARGET_PKGS
apk --no-cache add util-linux # Linux tools still needed and they might be removed if pulled by dependencies.
rm -rf /tmp/tigervnc
