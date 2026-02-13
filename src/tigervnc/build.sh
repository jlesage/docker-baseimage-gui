#!/bin/sh
#
# Helper script that builds the TigerVNC server, with most dependencies linked
# statically.
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
TIGERVNC_VERSION=1.16.0
XSERVER_VERSION=21.1.21

# Use the same versions has Alpine 3.21.
GMP_VERSION=6.3.0
NETTLE_VERSION=3.10
GNUTLS_VERSION=3.8.5
LIBXFONT2_VERSION=2.0.7
LIBFONTENC_VERSION=1.1.8
LIBTASN1_VERSION=4.20.0
LIBXSHMFENCE_VERSION=1.3.2
LIBXXF86VM_VERSION=1.1.5
LIBDRM_VERSION=2.4.123
# If the XKeyboardConfig version is too recent compared to xorgproto/libX11,
# xkbcomp will complain with warnings like "Could not resolve keysym ...".
XKEYBOARDCONFIG_VERSION=2.43
XKBCOMP_VERSION=1.4.7
PIXMAN_VERSION=0.43.4
BROTLI_VERSION=1.1.0
MESA_VERSION=24.2.8
LLVM_VERSION=19.1.4

# Define software download URLs.
TIGERVNC_URL=https://github.com/TigerVNC/tigervnc/archive/v${TIGERVNC_VERSION}.tar.gz
XSERVER_URL=https://www.x.org/releases/individual/xserver/xorg-server-${XSERVER_VERSION}.tar.gz

GMP_URL=https://ftp.gnu.org/gnu/gmp/gmp-${GMP_VERSION}.tar.xz
NETTLE_URL=https://ftp.gnu.org/gnu/nettle/nettle-${NETTLE_VERSION}.tar.gz
GNUTLS_URL=https://www.gnupg.org/ftp/gcrypt/gnutls/v${GNUTLS_VERSION%.*}/gnutls-${GNUTLS_VERSION}.tar.xz
LIBXFONT2_URL=https://www.x.org/pub/individual/lib/libXfont2-${LIBXFONT2_VERSION}.tar.gz
LIBFONTENC_URL=https://www.x.org/releases/individual/lib/libfontenc-${LIBFONTENC_VERSION}.tar.gz
LIBTASN1_URL=https://ftp.gnu.org/gnu/libtasn1/libtasn1-${LIBTASN1_VERSION}.tar.gz
LIBXSHMFENCE_URL=https://www.x.org/releases/individual/lib/libxshmfence-${LIBXSHMFENCE_VERSION}.tar.gz
LIBXXF86VM_URL=https://www.x.org/releases/individual/lib/libXxf86vm-${LIBXXF86VM_VERSION}.tar.xz
LIBDRM_URL=https://dri.freedesktop.org/libdrm/libdrm-${LIBDRM_VERSION}.tar.xz
PIXMAN_URL=https://www.x.org/releases/individual/lib/pixman-${PIXMAN_VERSION}.tar.xz
BROTLI_URL=https://github.com/google/brotli/archive/refs/tags/v${BROTLI_VERSION}.tar.gz
MESA_URL=https://archive.mesa3d.org/mesa-${MESA_VERSION}.tar.xz
LLVM_URL=https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/llvm-project-${LLVM_VERSION}.src.tar.xz

XKEYBOARDCONFIG_URL=https://www.x.org/archive/individual/data/xkeyboard-config/xkeyboard-config-${XKEYBOARDCONFIG_VERSION}.tar.xz
XKBCOMP_URL=https://www.x.org/releases/individual/app/xkbcomp-${XKBCOMP_VERSION}.tar.xz

# Set same default compilation flags as abuild.
export CFLAGS="-Os -fomit-frame-pointer -fno-plt"
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="$CFLAGS"
export LDFLAGS="-fuse-ld=mold -Wl,--as-needed,-O1,--sort-common -Wl,--strip-all"

export CC=xx-clang
export CXX=xx-clang++

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log() {
    echo ">>> $*"
}

to_cmake_cpu_family() {
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

to_llvm_target() {
    _arch=
    case "$1" in
        amd64|x86_64)
            _arch="X86"
            ;;
        386|i386)
            _arch="X86";
            ;;
        arm64|aarch64)
            _arch="AArch64";
            ;;
        arm|armv7l|armv6l)
            _arch="ARM";
            ;;
        *)
            echo "ERROR: Unknown arch '$1'."
            exit 1
            ;;
    esac
    # AMDGPU is needed for the Mesa AMD drivers.
    echo "$_arch;AMDGPU"
}

#
# Install required packages.
#
HOST_PKGS="\
    bash \
    curl \
    build-base \
    patchelf \
    abuild \
    file \
    clang \
    mold \
    llvm \
    cmake \
    autoconf \
    automake \
    libtool \
    pkgconf \
    bison \
    flex \
    py3-cparser \
    py3-mako \
    py3-yaml \
    py3-setuptools \
    meson \
    util-macros \
    font-util-dev \
    xtrans \
    xz \
"

# For llvm-tblgen. Must use the same version that we are building.
HOST_PKGS="$HOST_PKGS \
    llvm${LLVM_VERSION%%\.*} \
"

# For the Intel CLC compiler.
case "$(xx-info march)" in
    amd64|x86_64|386|i386)
        HOST_PKGS="$HOST_PKGS \
            spirv-llvm-translator \
        "
        ;;
esac

TARGET_PKGS="\
    g++ \
    xcb-util-dev \
    libx11-dev \
    libgcrypt-dev \
    libgcrypt-static \
    libgpg-error-static \
    libxkbfile-dev \
    libjpeg-turbo-dev \
    libunistring-dev \
    fltk-dev \
    libxrandr-dev \
    libxtst-dev \
    freetype-dev \
    zlib-dev \
    zstd-dev \
    libx11-static \
    libxcb-static \
    zlib-static \
    libjpeg-turbo-static \
    freetype-static \
    libpng-static \
    bzip2-static \
    libunistring-static \
    gettext-static \
    libunistring-dev \
    elfutils-dev \
    libbsd-dev \
    libbsd-static \
    libidn2-static \
    libxext-static \
    libxcb-static \
"

log "Installing required Alpine packages..."
apk --no-cache add $HOST_PKGS
apk --no-cache --repository http://dl-cdn.alpinelinux.org/alpine/v3.22/community add mold
xx-apk --no-cache --no-scripts add $TARGET_PKGS

echo "[binaries]
pkgconfig = '$(xx-info)-pkg-config'
llvm-config = '$(xx-info sysroot)usr/bin/llvm-config'
strip = '$(xx-info)-strip'

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
        --disable-cxx \
        --enable-static \
        --enable-shared \
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
        --enable-shared \
)
log "Compiling libtasn1..."
make -C /tmp/libtasn1 -j$(nproc)
log "Installing libtasn1..."
make DESTDIR=$(xx-info sysroot) -C /tmp/libtasn1 install
find $(xx-info sysroot)usr/lib -name "*.la" -delete

#
# Build Nettle.
# Build the library ourself to avoid the link error with arm64 and mold:
# mold: error: /aarch64-alpine-linux-musl/usr/lib/libnettle.a(fat-arm64.o):(.text): relocation R_AARCH64_LD64_GOTPAGE_LO15 against stderr out of range: 35928 is not in [0, 32768)
#
mkdir /tmp/nettle
log "Downloading Nettle..."
curl -# -L -f ${NETTLE_URL} | tar -xz --strip 1 -C /tmp/nettle
log "Configuring Nettle..."
(
    cd /tmp/nettle && ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
        --enable-fat \
        --disable-documentation \
        --disable-openssl \
        --enable-static \
        --enable-shared \
)
log "Compiling Nettle..."
make -C /tmp/nettle -j$(nproc)
find /tmp/nettle -type f -name "*.pc" -exec sed -i -e 's/ \#.*//' {} ';'
log "Installing Nettle..."
make DESTDIR=$(xx-info sysroot) -C /tmp/nettle install
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
        --with-system-priority-file= \
        --enable-static \
        --enable-shared \
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
        --enable-shared \
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
        --enable-shared \
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
        --enable-shared \
        --enable-futex \
)
log "Compiling libxshmfence..."
make -C /tmp/libxshmfence -j$(nproc)
log "Installing libxshmfence..."
make DESTDIR=$(xx-info sysroot) -C /tmp/libxshmfence install
find $(xx-info sysroot)usr/lib -name "*.la" -delete

#
# Build libxxf86vm
# The static library is not provided by Alpine repository, so we need to build
# it ourself.
#
mkdir /tmp/libxxf86vm
log "Downloading libxxf86vm..."
curl -# -L -f ${LIBXXF86VM_URL} | tar -xJ --strip 1 -C /tmp/libxxf86vm
log "Configuring libxxf86vm..."
(
    cd /tmp/libxxf86vm && ./configure \
        --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
        --host=$(xx-clang --print-target-triple) \
        --prefix=/usr \
        --enable-malloc0returnsnull \
        --enable-static \
        --enable-shared \
)
log "Compiling libxxf86vm..."
make -C /tmp/libxxf86vm -j$(nproc)
log "Installing libxxf86vm..."
make DESTDIR=$(xx-info sysroot) -C /tmp/libxxf86vm install
find $(xx-info sysroot)usr/lib -name "*.la" -delete

#
# Build libdrm.
# Mesa requires a more recent version than what is provided by Alpine
# repository.
#
mkdir /tmp/libdrm
log "Downloading libdrm..."
curl -# -L -f ${LIBDRM_URL} | tar -xJ --strip 1 -C /tmp/libdrm
log "Configuring libdrm..."
(
    cd /tmp/libdrm && \
    CFLAGS="$CFLAGS -O2" \
    CPPFLAGS="$CPPFLAGS -O2" \
    CXXFLAGS="$CXXFLAGS -O2" \
    abuild-meson \
        -Db_lto=false \
        -Ddefault_library=shared \
        -Dfreedreno=enabled \
        -Dintel=enabled \
        -Dtegra=enabled \
        -Domap=enabled \
        -Dexynos=enabled \
        -Dvc4=enabled \
        -Detnaviv=enabled \
        -Dudev=true \
        -Dinstall-test-programs=false \
        -Dtests=false \
        --cross-file /tmp/meson-cross.txt \
        . build
)
log "Compiling libdrm..."
meson compile -C /tmp/libdrm/build
log "Installing libdrm..."
DESTDIR=$(xx-info sysroot) meson install --no-rebuild -C /tmp/libdrm/build
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
# Build LLVM
# Building the minimum required reduces the final size by at least 20MB
# compared to using the version from Alpine repository.
#
mkdir /tmp/llvm
log "Downloading LLVM..."
curl -# -L -f ${LLVM_URL} | tar -xJ --strip 1 -C /tmp/llvm
log "Patching LLVM..."
patch -p1 -d /tmp/llvm < "$SCRIPT_DIR"/llvm-fix-memory-mf_exec-on-aarch64.patch
patch -p1 -d /tmp/llvm < "$SCRIPT_DIR"/llvm-install-prefix.patch
patch -p1 -d /tmp/llvm < "$SCRIPT_DIR"/llvm-stack-size.patch

log "Configuring LLVM..."
# NOTE: LLVM_BUILD_TOOLS=ON is needed to get `llvm-config`.
(
    cmake -B /tmp/llvm/build -S /tmp/llvm/llvm -G Ninja -Wno-dev \
        -DCMAKE_BUILD_TYPE=MinSizeRel \
        $(xx-clang --print-cmake-defines) \
        -DCMAKE_FIND_ROOT_PATH=$(xx-info sysroot) \
        -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DLLVM_ENABLE_PROJECTS="llvm" \
        -DLLVM_TABLEGEN=/usr/lib/llvm${LLVM_VERSION%%\.*}/bin/llvm-tblgen \
        -DLLVM_DEFAULT_TARGET_TRIPLE="$(xx-info)" \
        -DLLVM_TARGETS_TO_BUILD="$(to_llvm_target $(xx-info march))" \
        -DLLVM_ENABLE_DUMP=OFF \
        -DLLVM_ENABLE_SPHINX=OFF \
        -DLLVM_ENABLE_LIBCXX=OFF \
        -DLLVM_ENABLE_LIBEDIT=OFF \
        -DLLVM_ENABLE_ASSERTIONS=OFF \
        -DLLVM_ENABLE_EXPENSIVE_CHECKS=OFF \
        -DLLVM_ENABLE_RTTI=OFF \
        -DLLVM_ENABLE_EH=OFF \
        -DLLVM_ENABLE_TERMINFO=OFF \
        -DLLVM_ENABLE_ZLIB=OFF \
        -DLLVM_ENABLE_LIBXML2=OFF \
        -DLLVM_INCLUDE_TESTS=OFF \
        -DLLVM_INCLUDE_EXAMPLES=OFF \
        -DLLVM_INCLUDE_BENCHMARKS=OFF \
        -DLLVM_BUILD_TOOLS=ON \
        -DLLVM_BUILD_UTILS=OFF \
        -DLLVM_BUILD_TESTS=OFF \
        -DLLVM_BUILD_DOCS=OFF \
        -DLLVM_BUILD_EXAMPLES=OFF \
        -DLLVM_BUILD_EXTERNAL_COMPILER_RT=OFF \
        -DLLVM_BUILD_LLVM_DYLIB=OFF \
        -DLLVM_LINK_LLVM_DYLIB=OFF \
        -DBUILD_SHARED_LIBS=OFF \
)

log "Compiling LLVM..."
cmake --build /tmp/llvm/build
log "Installing LLVM..."
DESTDIR="$(xx-info sysroot)" cmake --install /tmp/llvm/build
if xx-info is-cross; then
    patchelf --set-interpreter "$(xx-info sysroot)"/"$(patchelf --print-interpreter "$(xx-info sysroot)"/usr/bin/llvm-config)" "$(xx-info sysroot)"/usr/bin/llvm-config
    patchelf --set-rpath "$(xx-info sysroot)"/usr/lib "$(xx-info sysroot)"/usr/bin/llvm-config
fi

#
# Build mesa.
# The static library is not provided by Alpine repository, so we need to build
# it ourself.
#
mkdir /tmp/mesa
log "Downloading mesa..."
curl -# -L -f ${MESA_URL} | tar -xJ --strip 1 -C /tmp/mesa
log "Patching mesa..."
patch -p1 -d /tmp/mesa < "$SCRIPT_DIR"/mesa-gl-static-lib.patch
patch -p1 -d /tmp/mesa < "$SCRIPT_DIR"/mesa-util-format-Check-for-NEON-before-using-it.patch
patch -p1 -d /tmp/mesa < "$SCRIPT_DIR"/mesa-add-llvm-module-selectiondag.patch

log "Configuring mesa..."
(
    _gallium_drivers="r300,r600,radeonsi,nouveau,llvmpipe,virgl"
    case "$(xx-info alpine-arch)" in
        armhf|armv7)
            _gallium_drivers="$_gallium_drivers,vc4,v3d,freedreno,lima,panfrost,etnaviv,tegra"
            _gallium_drivers="${_gallium_drivers//r300,}"
            ;;
        aarch64)
            _gallium_drivers="$_gallium_drivers,vc4,v3d,freedreno,lima,panfrost,etnaviv,tegra"
            _gallium_drivers="${_gallium_drivers//r300,}"
            ;;
        x86|x86_64)
            _gallium_drivers="$_gallium_drivers,svga,i915,iris,crocus"
            ;;
        *)
            echo "ERROR: Unknown alpine architecture: $(xx-info alpine-arch)"
            exit 1
            ;;
    esac
    _cross_file=
    xx-info is-cross && _cross_file="--cross-file /tmp/meson-cross.txt"
    cd /tmp/mesa && \
    CFLAGS="-fno-omit-frame-pointer -O2 -g1" \
    CXXFLAGS="$CXXFLAGS -O2 -g1" \
    CPPFLAGS="$CPPFLAGS -O2 -g1" \
    abuild-meson \
        -Db_ndebug=true \
        -Db_lto=false \
        -Dallow-kcmp=enabled \
        -Dexpat=enabled \
        -Dintel-rt=disabled \
        -Dpower8=enabled \
        -Dshader-cache=enabled \
        -Dxlib-lease=enabled \
        -Dxmlconfig=enabled \
        -Dzstd=enabled \
        -Dbuild-tests=false \
        -Denable-glcpp-tests=false \
        -Ddri3=enabled \
        -Ddri-search-path=/opt/base/lib/dri \
        -Dgallium-drivers=$_gallium_drivers \
        -Dvulkan-drivers= \
        -Dplatforms=x11 \
        -Dllvm=enabled \
        -Dintel-clc=system \
        -Dshared-llvm=disabled \
        -Dshared-glapi=enabled \
        -Dgbm=enabled \
        -Dgbm-backends-path=/opt/base/lib/gbm \
        -Dglx=dri \
        -Dopengl=true \
        -Dosmesa=false \
        -Dgles1=disabled \
        -Dgles2=disabled \
        -Degl=disabled \
        -Dgallium-extra-hud=true \
        -Dgallium-nine=false \
        -Dgallium-rusticl=false \
        -Dgallium-opencl=disabled \
        -Dopencl-spirv=false \
        -Dgallium-va=disabled \
        -Dgallium-vdpau=disabled \
        -Dgallium-xa=disabled \
        -Dstrip=true \
        -Dcpp_rtti=false \
        -Dc_args="-ffunction-sections -fdata-sections" \
        -Dcpp_args="-ffunction-sections -fdata-sections" \
        -Dc_link_args="-Wl,--gc-sections" \
        -Dcpp_link_args="-Wl,--gc-sections" \
        $_cross_file \
        . build
    meson configure --no-pager /tmp/mesa/build
)

log "Compiling mesa..."
meson compile -C /tmp/mesa/build
log "Installing mesa..."
DESTDIR=$(xx-info sysroot) meson install --no-rebuild -C /tmp/mesa/build
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
TIGERVNC_PATCHES="
    /tmp/tigervnc/unix/xserver21.patch:/tmp/tigervnc/unix/xserver
    "$SCRIPT_DIR"/xserver-disable-unused-functions.patch:/tmp/tigervnc/unix/xserver
    "$SCRIPT_DIR"/xserver-dri-drivers-dir.patch:/tmp/tigervnc/unix/xserver
    "$SCRIPT_DIR"/disable-pam.patch:/tmp/tigervnc
    "$SCRIPT_DIR"/internal-conn-sec-types.patch:/tmp/tigervnc
"
for pdef in $TIGERVNC_PATCHES; do
    p="${pdef%:*}"
    d="${pdef#*:}"
    log "  --> Applying patch $(basename "$p")..."
    patch -p1 -d "$d" < "$p"
done

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
        LDFLAGS="$LDFLAGS -Wl,--allow-shlib-undefined" \
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
        --enable-libdrm \
        --disable-dri \
        --enable-dri2 \
        --enable-dri3 \
        --enable-present \
        --disable-xvfb \
        --enable-glx \
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

log "Relinking vncpasswd as static binary..."
(
    cd /tmp/tigervnc/unix/vncpasswd
    xx-clang++ $CXXFLAGS $LDFLAGS --static -static \
        -o vncpasswd \
        CMakeFiles/vncpasswd.dir/vncpasswd.cxx.o \
        ../../common/rfb/librfb.a \
        ../../common/core/libcore.a \
        ../../common/rdr/librdr.a \
)

log "Relinking Xvnc binary with static libraries..."
(
    cd /tmp/tigervnc/unix/xserver/hw/vnc
    xx-clang++ $CXXFLAGS $LDFLAGS \
        '-Wl,-rpath,$ORIGIN/../lib' \
        -o Xvnc \
        Xvnc-xvnc.o \
        Xvnc-stubs.o \
        Xvnc-miinitext.o \
        Xvnc-buildtime.o \
        Xvnc-vncDRI3.o \
        Xvnc-vncDRI3Draw.o \
        ../../fb/.libs/libfb.a \
        ../../xfixes/.libs/libxfixes.a \
        ../../Xext/.libs/libXext.a \
        ../../dbe/.libs/libdbe.a \
        ../../glx/.libs/libglx.a \
        ../../glx/.libs/libglxvnd.a \
        ../../randr/.libs/librandr.a \
        ../../render/.libs/librender.a \
        ../../damageext/.libs/libdamageext.a \
        ../../present/.libs/libpresent.a \
        ../../miext/sync/.libs/libsync.a \
        ../../miext/damage/.libs/libdamage.a \
        ../../miext/shadow/.libs/libshadow.a \
        ../../Xi/.libs/libXi.a \
        ../../xkb/.libs/libxkb.a \
        ../../xkb/.libs/libxkbstubs.a \
        ../../composite/.libs/libcomposite.a \
        ../../dix/.libs/libmain.a \
        ../../dix/.libs/libdix.a \
        ../../mi/.libs/libmi.a \
        ../../os/.libs/libos.a \
        ../../dri3/.libs/libdri3.a \
        ./.libs/libvnccommon.a \
        ../../../../common/network/libnetwork.a \
        ../../../../common/rfb/librfb.a \
        ../../../../common/rdr/librdr.a \
        ../../../../common/core/libcore.a \
        ../../../../unix/common/libunixcommon.a \
        $(xx-info sysroot)usr/lib/libXau.a \
        $(xx-info sysroot)usr/lib/libXdmcp.a \
        $(xx-info sysroot)usr/lib/libpixman-1.a \
        $(xx-info sysroot)usr/lib/libjpeg.a \
        $(xx-info sysroot)usr/lib/libXfont2.a \
        $(xx-info sysroot)usr/lib/libfreetype.a \
        $(xx-info sysroot)usr/lib/libfontenc.a \
        $(xx-info sysroot)usr/lib/libpng16.a \
        $(xx-info sysroot)usr/lib/libbrotlidec.a \
        $(xx-info sysroot)usr/lib/libbrotlicommon.a \
        $(xx-info sysroot)usr/lib/libbz2.a \
        $(xx-info sysroot)usr/lib/libgnutls.a \
        $(xx-info sysroot)usr/lib/libhogweed.a \
        $(xx-info sysroot)usr/lib/libgbm.a \
        $(xx-info sysroot)usr/lib/libgmp.a \
        $(xx-info sysroot)usr/lib/libnettle.a \
        $(xx-info sysroot)usr/lib/libunistring.a \
        $(xx-info sysroot)usr/lib/libtasn1.a \
        $(xx-info sysroot)usr/lib/libbsd.a \
        $(xx-info sysroot)usr/lib/libmd.a \
        $(xx-info sysroot)usr/lib/libintl.a \
        $(xx-info sysroot)usr/lib/libidn2.a \
        $(xx-info sysroot)usr/lib/libGL.a \
        $(xx-info sysroot)usr/lib/libXext.a \
        $(xx-info sysroot)usr/lib/libxcb.a \
        $(xx-info sysroot)usr/lib/libxcb-dri2.a \
        $(xx-info sysroot)usr/lib/libxcb-dri3.a \
        $(xx-info sysroot)usr/lib/libxcb-glx.a \
        $(xx-info sysroot)usr/lib/libxcb-present.a \
        $(xx-info sysroot)usr/lib/libxcb-randr.a \
        $(xx-info sysroot)usr/lib/libxcb-shm.a \
        $(xx-info sysroot)usr/lib/libxcb-sync.a \
        $(xx-info sysroot)usr/lib/libxcb-xfixes.a \
        $(xx-info sysroot)usr/lib/libX11.a \
        $(xx-info sysroot)usr/lib/libX11-xcb.a \
        $(xx-info sysroot)usr/lib/libXfixes.a \
        $(xx-info sysroot)usr/lib/libxshmfence.a \
        $(xx-info sysroot)usr/lib/libXxf86vm.a \
        -pthread \
        -lgallium-24.2.8 \
        -ldrm \
        -lexpat \
        -lz \
        -lglapi \
)

log "Installing TigerVNC server..."
make DESTDIR=/tmp/tigervnc-install -C /tmp/tigervnc/unix/xserver install

log "Installing TigerVNC vncpasswd tool..."
make DESTDIR=/tmp/tigervnc-install -C /tmp/tigervnc/unix/vncpasswd install

log "Creating TigerVNC rootfs..."
TIGERVNC_BASE_DIR=/opt/base
TIGERVNC_ROOTFS_DIR=/tmp/tigervnc-rootfs
TIGERVNC_ROOTFS_BASE_DIR="$TIGERVNC_ROOTFS_DIR"/"$TIGERVNC_BASE_DIR"
mkdir -p "$TIGERVNC_ROOTFS_BASE_DIR"/bin "$TIGERVNC_ROOTFS_BASE_DIR"/lib
cp -av /tmp/tigervnc-install/usr/bin/Xvnc "$TIGERVNC_ROOTFS_BASE_DIR"/bin/
cp -av /tmp/tigervnc-install/usr/bin/vncpasswd "$TIGERVNC_ROOTFS_BASE_DIR"/bin/
cp -av $(xx-info sysroot)usr/lib/dri "$TIGERVNC_ROOTFS_BASE_DIR"/lib/

# Setup LDD for cross-compilation.
LDD_PREFIX=
case "$(xx-info alpine-arch)" in
    armhf)
        LDD_PREFIX=armv6-alpine-linux-musleabihf-
        apk --no-cache add binutils-armhf
        ;;
    armv7)
        LDD_PREFIX=armv7-alpine-linux-musleabihf-
        apk --no-cache add binutils-armv7
        ;;
    aarch64)
        LDD_PREFIX=aarch64-alpine-linux-musl-
        apk --no-cache add binutils-aarch64
        ;;
    x86)
        LDD_PREFIX=i586-alpine-linux-musl-
        apk --no-cache add binutils-x86
        ;;
    x86_64)
        ;;
    *)
        echo "ERROR: Unknown alpine architecture: $(xx-info alpine-arch)"
        exit 1
        ;;
esac
LDD="${LDD_PREFIX}ldd"
if [ -n "$LDD_PREFIX" ]; then
    export CT_XLDD_VERBOSE=1
    export CT_XLDD_SYSROOT="$(xx-info sysroot)"
    ln -sv "$SCRIPT_DIR/cross-compile-ldd" "/usr/bin/$LDD"
    echo '/lib' >>  $(xx-info sysroot)/etc/ld.so.conf
    echo '/usr/lib' >>  $(xx-info sysroot)/etc/ld.so.conf
fi

find "$TIGERVNC_ROOTFS_BASE_DIR" -type f | xargs file | grep -w ELF | grep "dynamically linked" | cut -d : -f 1 | while read BIN
do
    RAW_DEPS="$($LDD "$BIN")"
    echo "Dependencies for $BIN:"
    echo "================================"
    echo "$RAW_DEPS"
    echo "================================"

    if echo "$RAW_DEPS" | grep -q " not found"; then
        echo "ERROR: Some libraries are missing!"
        exit 1
    fi

    $LDD "$BIN" | (grep " => " || true) | cut -d'>' -f2 | sed 's/^[[:space:]]*//' | cut -d'(' -f1 | while read dep
    do
        dep="$(xx-info sysroot)$dep"
        dep_real="$(realpath "$dep")"
        dep_basename="$(basename "$dep_real")"

        # Skip already-processed libraries.
        [ ! -f "$TIGERVNC_ROOTFS_BASE_DIR/lib/$dep_basename" ] || continue

        echo "  -> Found library: $dep"
        cp "$dep_real" "$TIGERVNC_ROOTFS_BASE_DIR"/lib/
        while true; do
            [ -L "$dep" ] || break;
            ln -sf "$dep_basename" "$TIGERVNC_ROOTFS_BASE_DIR"/lib/$(basename $dep)
            dep="$(readlink -f "$dep")"
        done

        if echo "$dep_basename" | grep -q "^ld-"; then
            echo "$dep_basename" > /tmp/interpreter_fname
            echo "    -> This is the interpreter."
        fi
    done
done

INTERPRETER_FNAME="$(cat /tmp/interpreter_fname 2>/dev/null)"
if [ -z "$INTERPRETER_FNAME" ]; then
    echo "ERROR: Interpreter not found!"
    exit 1
fi

log "Patching ELF of binaries..."
find "$TIGERVNC_ROOTFS_BASE_DIR"/bin -type f -executable -exec echo "  -> Setting interpreter of {}..." ';' -exec patchelf --set-interpreter "$TIGERVNC_BASE_DIR/lib/$INTERPRETER_FNAME" {} ';'
# NOTE: Avoid setting the rpath with patchelf: this causes UPX 4.x to fail
#       compress the binary: `CantPackException: bad DT_STRSZ 0x15b8`. This has
#       been fixed in UPX 5.x, which can't be used due to its incompatibility
#       with old kernels.
# NOTE: The only dynamically-linked binary is Xvnc, for which rpath is set at
#       compile time as workaround.
#find "$TIGERVNC_ROOTFS_BASE_DIR"/bin -type f -executable ! -name Xvnc -exec echo "  -> Setting rpath of {}..." ';' -exec patchelf --set-rpath '$ORIGIN/../lib' {} ';'

log "Patching ELF of libraries..."
find "$TIGERVNC_ROOTFS_BASE_DIR"/lib -maxdepth 1 -type f -name "lib*" -exec echo "  -> Setting rpath of {}..." ';' -exec patchelf --set-rpath '$ORIGIN' {} ';'
find "$TIGERVNC_ROOTFS_BASE_DIR"/lib/dri -maxdepth 1 -type f -name "lib*" -exec echo "  -> Setting rpath of {}..." ';' -exec patchelf --set-rpath '$ORIGIN/../lib' {} ';'

#
# Cleanup.
#
log "Performing cleanup..."
apk --no-cache del $HOST_PKGS
xx-apk --no-cache --no-scripts del $TARGET_PKGS
apk --no-cache add util-linux # Linux tools still needed and they might be removed if pulled by dependencies.
rm -rf \
    /tmp/gmp \
    /tmp/libtasn1 \
    /tmp/gnutls \
    /tmp/libfontenc \
    /tmp/libxfont2 \
    /tmp/libxshmfence \
    /tmp/libxxf86vm \
    /tmp/libdrm \
    /tmp/pixman \
    /tmp/brotli \
    /tmp/llvm \
    /tmp/mesa \
    /tmp/tigervnc \

