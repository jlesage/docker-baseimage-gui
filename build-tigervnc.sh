#!/bin/sh
#
# Helper script that builds the TigerVNC server as a static binary.
#
# NOTE: This script should run under Alpine Linux 3.14.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Define software versions.
TIGERVNC_VERSION=1.11.0
XSERVER_VERSION=1.20.13

GNUTLS_VERSION=3.7.1
LIBXFONT2_VERSION=2.0.4
LIBFONTENC_VERSION=1.1.4
LIBTASN1_VERSION=4.17.0

# Define software download URLs.
TIGERVNC_URL=https://github.com/TigerVNC/tigervnc/archive/v${TIGERVNC_VERSION}.tar.gz
XSERVER_URL=https://github.com/freedesktop/xorg-xserver/archive/xorg-server-${XSERVER_VERSION}.tar.gz

GNUTLS_URL=https://www.gnupg.org/ftp/gcrypt/gnutls/v${GNUTLS_VERSION%.*}/gnutls-${GNUTLS_VERSION}.tar.xz
LIBXFONT2_URL=https://www.x.org/pub/individual/lib/libXfont2-${LIBXFONT2_VERSION}.tar.bz2
LIBFONTENC_URL=https://www.x.org/releases/individual/lib/libfontenc-${LIBFONTENC_VERSION}.tar.bz2
LIBTASN1_URL=https://ftp.gnu.org/gnu/libtasn1/libtasn1-${LIBTASN1_VERSION}.tar.gz

# Set same default compilation flags as abuild.
export CFLAGS="-Os -fomit-frame-pointer"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS="-Wl,--as-needed"

function log {
    echo ">>> $*"
}

# Install required packages.
log "Installing required Alpine packages..."
apk --no-cache add \
    curl \
    build-base \
    cmake \
    autoconf \
    automake \
    libtool \
    xcb-util-dev \
    xtrans \
    font-util-dev \
    pixman-dev \
    libx11-dev \
    libgcrypt-dev \
    libxkbfile-dev \
    libxfont2-dev \
    libjpeg-turbo-dev \
    gnutls-dev \
    fltk-dev \
    libxrandr-dev \
    libxtst-dev \
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
curl -# -L ${GNUTLS_URL} | tar -xJ --strip 1 -C /tmp/gnutls
log "Configuring GNU TLS..."
(
    cd /tmp/gnutls && ./configure \
        --prefix=/usr \
        --disable-openssl-compatibility \
        --disable-rpath \
        --disable-guile \
        --disable-valgrind-tests \
        --without-p11-kit \
        --disable-tools \
        --enable-static \
        --disable-shared \
)
log "Compiling GNU TLS..."
make -C /tmp/gnutls -j$(nproc)
log "Installing GNU TLS..."
make DESTDIR=/tmp/static-libs -C /tmp/gnutls install

#
# Build libxfont2
# The static library is not provided by Alpine repository, so we need to build
# it ourself.
#
mkdir /tmp/libxfont2
log "Downloading libxfont2..."
curl -# -L ${LIBXFONT2_URL} | tar -xj --strip 1 -C /tmp/libxfont2
log "Configuring libxfont2..."
(
    cd /tmp/libxfont2 && ./configure \
        -prefix=/usr \
        --without-fop \
        --enable-static \
        --disable-shared \
)
log "Compiling libxfont2..."
make -C /tmp/libxfont2 -j$(nproc)
log "Installing libxfont2..."
make DESTDIR=/tmp/static-libs -C /tmp/libxfont2 install

#
# Build libfontenc
# The static library is not provided by Alpine repository, so we need to build
# it ourself.
#
mkdir /tmp/libfontenc
log "Downloading libfontenc..."
curl -# -L ${LIBFONTENC_URL} | tar -xj --strip 1 -C /tmp/libfontenc
log "Configuring libfontenc..."
(
    cd /tmp/libfontenc && ./configure \
        --prefix=/usr \
        --with-encodingsdir=/usr/share/fonts/encodings \
        --enable-static \
        --disable-shared \
)
log "Compiling libfontenc..."
make -C /tmp/libfontenc -j$(nproc)
log "Installing libfontenc..."
make DESTDIR=/tmp/static-libs -C /tmp/libfontenc install

#
# Build libtasn1
# The static library is not provided by Alpine repository, so we need to build
# it ourself.
#
mkdir /tmp/libtasn1
log "Downloading libtasn1..."
curl -# -L ${LIBTASN1_URL} | tar -xz --strip 1 -C /tmp/libtasn1
log "Configuring libtasn1..."
(
    cd /tmp/libtasn1 && CFLAGS="$CFLAGS -Wno-error=inline" ./configure \
        -prefix=/usr \
        --enable-static \
        --disable-shared \
)
log "Compiling libtasn1..."
make -C /tmp/libtasn1 -j$(nproc)
log "Installing libtasn1..."
make DESTDIR=/tmp/static-libs -C /tmp/libtasn1 install

#
# Install all static libraries.
#
log "Installing static libraries..."
cp -av /tmp/static-libs/usr/lib/*.a /usr/lib/

#
# Build TigerVNC
#
mkdir /tmp/tigervnc
log "Downloading TigerVNC..."
curl -# -L ${TIGERVNC_URL} | tar -xz --strip 1 -C /tmp/tigervnc
log "Downloading Xorg server..."
curl -# -L ${XSERVER_URL} | tar -xz --strip 1 -C /tmp/tigervnc/unix/xserver

log "Patching TigerVNC..."
# Apply the TigerVNC patch against the X server.
patch -p1 -d /tmp/tigervnc/unix/xserver < /tmp/tigervnc/unix/xserver120.patch
# Add the ability to listen on both Unix socket and TCP port.
curl -# -L https://github.com/TigerVNC/tigervnc/commit/701605e.patch | patch -p1 -d /tmp/tigervnc
# Build a static binary of vncpasswd.
sed 's/target_link_libraries(vncpasswd tx rfb os)/target_link_libraries(vncpasswd -static tx rfb os)/' -i /tmp/tigervnc/unix/vncpasswd/CMakeLists.txt
# Disable PAM support.
sed 's/if(UNIX AND NOT APPLE)/if(USE_LINUX_PAM)/' -i /tmp/tigervnc/CMakeLists.txt
sed 's/if(UNIX AND NOT APPLE)/if(USE_LINUX_PAM)/' -i /tmp/tigervnc/common/rfb/CMakeLists.txt
sed 's/#if !defined(WIN32) && !defined(__APPLE__)/#if defined(USE_LINUX_PAM)/' -i  /tmp/tigervnc/common/rfb/SSecurityPlain.cxx
sed 's/#elif !defined(__APPLE__)/#elif defined(USE_LINUX_PAM)/' -i  /tmp/tigervnc/common/rfb/SSecurityPlain.cxx

log "Configuring TigerVNC..."
(
    cd /tmp/tigervnc && cmake -G "Unix Makefiles" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release \
        -DINSTALL_SYSTEMD_UNITS=OFF \
        -DENABLE_NLS=OFF \
        -DENABLE_GNUTLS=ON \
        -DBUILD_VIEWER=OFF \
)

log "Compiling TigerVNC common libraries and tools..."
make -C /tmp/tigervnc/common -j$(nproc)
make -C /tmp/tigervnc/unix/common -j$(nproc)
make -C /tmp/tigervnc/unix/vncpasswd -j$(nproc)

log "Configuring TigerVNC server..."
autoreconf -fiv /tmp/tigervnc/unix/xserver
(
    cd /tmp/tigervnc/unix/xserver && ./configure \
        --prefix=/usr \
        --sysconfdir=/etc/X11 \
        --localstatedir=/var \
        --with-xkb-path=/usr/share/X11/xkb \
        --with-xkb-output=/var/lib/xkb \
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
        --disable-screensaver \
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
make -C /tmp/tigervnc/unix/xserver -j$(nproc)

# Now it's time to do a static binary of the TigerVNC server.

log "Preparing creation of TigerVNC server static binary..."
# First, remove all dependencies on dynamic libraries.
find /tmp/tigervnc -name "*.la" -exec sed 's/^dependency_libs/#dependency_libs/' -i {} ';'
# Then, adjust linker flags in the Makefile.
sed 's/^XSERVER_SYS_LIBS = .*/XSERVER_SYS_LIBS = -l:libXau.a -l:libXdmcp.a -l:libpixman-1.a -l:libjpeg.a -l:libXfont2.a -l:libfreetype.a -l:libfontenc.a -l:libpng16.a -l:libbrotlidec.a -l:libbrotlicommon.a -l:libz.a -l:libbz2.a -l:libgnutls.a -l:libhogweed.a -l:libgmp.a -l:libnettle.a -l:libunistring.a -l:libtasn1.a -l:libbsd.a -l:libmd.a/' -i /tmp/tigervnc/unix/xserver/hw/vnc/Makefile
sed 's/^Xvnc_LDFLAGS = .*/Xvnc_LDFLAGS = -static --static -static-libgcc -static-libstdc++/' -i /tmp/tigervnc/unix/xserver/hw/vnc/Makefile
sed 's/-lX11/-l:libX11.a/' -i /tmp/tigervnc/unix/xserver/hw/vnc/Makefile

# Finally, recreate the binary.
log "Creating TigerVNC server static binary..."
rm /tmp/tigervnc/unix/xserver/hw/vnc/Xvnc
make -C /tmp/tigervnc/unix/xserver/hw/vnc/

# Install TigerVNC server.
log "Installing TigerVNC server..."
make DESTDIR=/tmp/tigervnc-install -C /tmp/tigervnc/unix/xserver install
strip /tmp/tigervnc-install/usr/bin/Xvnc

# Install TigerVNC vncpasswd tool.
log "Installing TigerVNC vncpasswd tool..."
make DESTDIR=/tmp/tigervnc-install -C /tmp/tigervnc/unix/vncpasswd install
strip /tmp/tigervnc-install/usr/bin/vncpasswd

