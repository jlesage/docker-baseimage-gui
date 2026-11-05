#!/bin/sh
# Build a self-contained microphone bridge with the shared xx/musl toolchain.
set -eu

GSTREAMER_VERSION=1.26.11
OPUS_VERSION=1.5.2
GSTREAMER_URL=https://gstreamer.freedesktop.org/src
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR=/tmp/microphone-gstreamer

export CC=xx-clang
export CXX=xx-clang++
export CFLAGS="-Os -fomit-frame-pointer -ffunction-sections -fdata-sections"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-Wl,--gc-sections"

SYSROOT="$(xx-info sysroot)"
export PKG_CONFIG="$(xx-info)-pkg-config"
# Static plugin metadata lives outside pkg-config's default library directory.
export PKG_CONFIG_PATH="${SYSROOT}usr/lib/gstreamer-1.0/pkgconfig"
mkdir -p "$BUILD_DIR"

build_gstreamer_module() {
    module="$1"
    shift
    archive="$BUILD_DIR/$module.tar.xz"
    source_dir="$BUILD_DIR/$module"
    echo ">>> Building static $module for ${TARGETPLATFORM}..."
    curl --fail --location --retry 3 \
        "$GSTREAMER_URL/$module/$module-$GSTREAMER_VERSION.tar.xz" --output "$archive"
    mkdir -p "$source_dir"
    tar -xJf "$archive" --strip-components=1 -C "$source_dir"
    meson setup "$source_dir/build" "$source_dir" \
        --cross-file "$BUILD_DIR/cross.ini" --wrap-mode=nofallback \
        --prefix=/usr --libdir=lib --buildtype=release \
        --default-library=static --auto-features=disabled -Dprefer_static=true \
        "$@"
    meson compile -C "$source_dir/build" -j"$(nproc)"
    DESTDIR="$SYSROOT" meson install --no-rebuild -C "$source_dir/build"
    rm -rf "$source_dir" "$archive"
}

build_opus() {
    # Alpine 3.20 ships no libopus.a. Build the same codec version for the target.
    opus_dir="$BUILD_DIR/opus"
    curl --fail --location --retry 3 \
        "https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz" \
        --output "$BUILD_DIR/opus.tar.gz"
    mkdir -p "$opus_dir"
    tar -xzf "$BUILD_DIR/opus.tar.gz" --strip-components=1 -C "$opus_dir"
    (
        cd "$opus_dir"
        AR=llvm-ar RANLIB=llvm-ranlib ./configure \
            --build="$(TARGETPLATFORM= xx-clang --print-target-triple)" \
            --host="$(xx-clang --print-target-triple)" \
            --prefix=/usr --libdir=/usr/lib \
            --enable-static --disable-shared --disable-extra-programs --disable-doc \
            --disable-asm
    )
    make -C "$opus_dir" -j"$(nproc)"
    DESTDIR="$SYSROOT" make -C "$opus_dir" install
    rm -rf "$opus_dir" "$BUILD_DIR/opus.tar.gz"
}

build_libraries() {
    # Build tools run on BUILDPLATFORM. All libraries/headers come from TARGETPLATFORM.
    apk --no-cache add curl clang lld llvm make meson ninja pkgconf python3 glib-dev flex bison
    xx-apk --no-cache --no-scripts add \
        gcc musl-dev glib-dev glib-static libffi-dev util-linux-static \
        libogg-dev libogg-static zlib-dev zlib-static

    # Meson's CPU family names differ from Docker's platform architecture names.
    case "$(xx-info arch)" in
        amd64) CPU_FAMILY=x86_64 ;;
        386) CPU_FAMILY=x86 ;;
        arm64) CPU_FAMILY=aarch64 ;;
        arm) CPU_FAMILY=arm ;;
        *) CPU_FAMILY="$(xx-info arch)" ;;
    esac
    cat > "$BUILD_DIR/cross.ini" <<CROSS
[binaries]
c = 'xx-clang'
cpp = 'xx-clang++'
ar = 'llvm-ar'
strip = 'llvm-strip'
pkg-config = '${PKG_CONFIG}'

[properties]
needs_exe_wrapper = true
sys_root = '${SYSROOT}'
pkg_config_libdir = '${SYSROOT}usr/lib/pkgconfig'

[host_machine]
system = 'linux'
cpu_family = '${CPU_FAMILY}'
cpu = '$(xx-info march)'
endian = 'little'
CROSS

    build_opus

    # No runtime scanner, loadable plugins, hardware backends, or optional codecs.
    # Keep this list aligned with the static plugin declarations in microphone.c.
    build_gstreamer_module gstreamer -Dregistry=false
    build_gstreamer_module gst-plugins-base \
        -Daudioconvert=enabled -Daudioresample=enabled -Dplayback=enabled \
        -Dtypefind=enabled -Dogg=enabled -Dopus=enabled
    build_gstreamer_module gst-plugins-good -Dmatroska=enabled

    rm -rf "$BUILD_DIR"
}

# Cache library compilation independently of changes to the service's C code.
case "${1:-all}" in
    libraries)
        build_libraries
        ;;
    binary)
        make -C "$SCRIPT_DIR" -j"$(nproc)"
        xx-verify --static "$SCRIPT_DIR/microphone"
        ;;
    all)
        build_libraries
        make -C "$SCRIPT_DIR" -j"$(nproc)"
        xx-verify --static "$SCRIPT_DIR/microphone"
        ;;
    *)
        echo "Usage: $0 [libraries|binary|all]" >&2
        exit 1
        ;;
esac
