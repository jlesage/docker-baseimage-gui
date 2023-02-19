# syntax=docker/dockerfile:1.4
#
# baseimage-gui Dockerfile
#
# https://github.com/jlesage/docker-baseimage-gui
#

ARG BASEIMAGE=unknown

# Define the Alpine packages to be installed into the image.
ARG ALPINE_PKGS="\
    # Needed to generate self-signed certificates
    openssl \
    # Needed to use netcat with unix socket.
    netcat-openbsd \
"

# Define the Debian/Ubuntu packages to be installed into the image.
ARG DEBIAN_PKGS="\
    # Used to determine if nginx is ready.
    netcat \
    # For ifconfig
    net-tools \
    # Needed to generate self-signed certificates
    openssl \
"

# Get Dockerfile cross-compilation helpers.
FROM --platform=$BUILDPLATFORM tonistiigi/xx AS xx

# Build UPX.
FROM --platform=$BUILDPLATFORM alpine:3.15 AS upx
RUN apk --no-cache add build-base curl make cmake git && \
    mkdir /tmp/upx && \
    curl -# -L https://github.com/upx/upx/releases/download/v4.0.1/upx-4.0.1-src.tar.xz | tar xJ --strip 1 -C /tmp/upx && \
    make -C /tmp/upx build/release-gcc -j$(nproc) && \
    cp -v /tmp/upx/build/release-gcc/upx /usr/bin/upx

# Build TigerVNC server.
FROM --platform=$BUILDPLATFORM alpine:3.15 AS tigervnc
ARG TARGETPLATFORM
COPY --from=xx / /
COPY src/tigervnc /build
RUN /build/build.sh
RUN xx-verify --static /tmp/tigervnc-install/usr/bin/Xvnc
RUN xx-verify --static /tmp/tigervnc-install/usr/bin/vncpasswd
COPY --from=upx /usr/bin/upx /usr/bin/upx
RUN upx /tmp/tigervnc-install/usr/bin/Xvnc
RUN upx /tmp/tigervnc-install/usr/bin/vncpasswd

# Build Fontconfig.
FROM --platform=$BUILDPLATFORM alpine:3.15 AS fontconfig
ARG TARGETPLATFORM
COPY --from=xx / /
COPY src/fontconfig/build.sh /tmp/build-fontconfig.sh
RUN /tmp/build-fontconfig.sh

# Build Openbox.
FROM --platform=$BUILDPLATFORM alpine:3.15 AS openbox
ARG TARGETPLATFORM
COPY --from=xx / /
COPY --from=fontconfig /tmp/fontconfig-install /tmp/fontconfig-install
COPY src/openbox /tmp/build
RUN /tmp/build/build.sh
RUN xx-verify --static \
    /tmp/openbox-install/usr/bin/openbox \
    /tmp/openbox-install/usr/bin/obxprop
COPY --from=upx /usr/bin/upx /usr/bin/upx
RUN upx /tmp/openbox-install/usr/bin/openbox
RUN upx /tmp/openbox-install/usr/bin/obxprop

# Build xdpyprobe.
# Used to determine if the X server (Xvnc) is ready.
FROM --platform=$BUILDPLATFORM alpine:3.15 AS xdpyprobe
ARG TARGETPLATFORM
COPY --from=xx / /
COPY src/xdpyprobe /tmp/xdpyprobe
RUN apk --no-cache add make clang
RUN xx-apk --no-cache add gcc musl-dev libx11-dev libx11-static libxcb-static
RUN CC=xx-clang \
    make -C /tmp/xdpyprobe
RUN xx-verify --static /tmp/xdpyprobe/xdpyprobe
COPY --from=upx /usr/bin/upx /usr/bin/upx
RUN upx /tmp/xdpyprobe/xdpyprobe

# Build yad.
FROM --platform=$BUILDPLATFORM alpine:3.15 AS yad
ARG TARGETPLATFORM
COPY --from=xx / /
COPY --from=fontconfig /tmp/fontconfig-install /tmp/fontconfig-install
COPY src/yad/build.sh /tmp/build-yad.sh
RUN /tmp/build-yad.sh
RUN xx-verify --static /tmp/yad-install/usr/bin/yad
COPY --from=upx /usr/bin/upx /usr/bin/upx
RUN upx /tmp/yad-install/usr/bin/yad

# Build Nginx.
FROM --platform=$BUILDPLATFORM alpine:3.15 AS nginx
ARG TARGETPLATFORM
COPY --from=xx / /
COPY src/nginx/build.sh /tmp/build-nginx.sh
RUN /tmp/build-nginx.sh
RUN xx-verify --static /tmp/nginx-install/sbin/nginx
COPY --from=upx /usr/bin/upx /usr/bin/upx
RUN upx /tmp/nginx-install/sbin/nginx
# NOTE: Extended attributes are kept by buildx when using the COPY command.
#       See https://wildwolf.name/multi-stage-docker-builds-and-xattrs/.
RUN apk --no-cache add libcap && setcap cap_net_bind_service=ep /tmp/nginx-install/sbin/nginx

# Build noVNC.
FROM --platform=$BUILDPLATFORM alpine:3.15 AS noVNC
ARG NOVNC_VERSION=1.4.0
ARG BOOTSTRAP_VERSION=5.1.3
ARG BOOTSTRAP_NIGHTSHADE_VERSION=1.1.3
ARG FONTAWESOME_VERSION=4.7.0
ARG NOVNC_URL=https://github.com/novnc/noVNC/archive/refs/tags/v${NOVNC_VERSION}.tar.gz
ARG BOOTSTRAP_URL=https://github.com/twbs/bootstrap/releases/download/v${BOOTSTRAP_VERSION}/bootstrap-${BOOTSTRAP_VERSION}-dist.zip
ARG BOOTSTRAP_NIGHTSHADE_URL=https://github.com/vinorodrigues/bootstrap-dark-5/archive/refs/tags/v${BOOTSTRAP_NIGHTSHADE_VERSION}.tar.gz
ARG FONTAWESOME_URL=https://fontawesome.com/v${FONTAWESOME_VERSION}/assets/font-awesome-${FONTAWESOME_VERSION}.zip
WORKDIR /tmp
COPY helpers/* /usr/bin/
COPY rootfs/opt/noVNC/index.html /opt/noVNC/index.html
RUN \
    # Install required tools.
    apk --no-cache add \
        curl \
        sed \
        jq \
        npm \
        && \
    npm install clean-css-cli -g
RUN \
    # Create required directories.
    mkdir -p \
        /opt/noVNC/app/styles \
        /opt/noVNC/app/fonts
RUN \
    # Install noVNC.
    mkdir /tmp/noVNC && \
    curl -# -L ${NOVNC_URL} | tar -xz --strip 1 -C /tmp/noVNC && \
    cp -vr /tmp/noVNC/core /opt/noVNC/ && \
    cp -vr /tmp/noVNC/vendor /opt/noVNC/
RUN \
    # Install Bootstrap.
    # NOTE: Only copy the JS bundle, since the CSS is taken from Bootstrap
    #       Nightshade.
    curl -sS -L -O ${BOOTSTRAP_URL} && \
    unzip bootstrap-${BOOTSTRAP_VERSION}-dist.zip && \
    #cp -v bootstrap-${BOOTSTRAP_VERSION}-dist/css/bootstrap.min.css /opt/noVNC/app/styles/ && \
    cp -v bootstrap-${BOOTSTRAP_VERSION}-dist/js/bootstrap.bundle.min.js* /opt/noVNC/app/
RUN \
    # Install Bootstrap Nightshade.
    mkdir /tmp/bootstrap-nightshade && \
    curl -# -L ${BOOTSTRAP_NIGHTSHADE_URL} | tar -xz --strip 1 -C /tmp/bootstrap-nightshade && \
    cleancss \
        -O1 \
        --format breakWith=lf \
        --output /opt/noVNC/app/styles/bootstrap-nightshade.min.css \
        /tmp/bootstrap-nightshade/dist/css/bootstrap-nightshade.css
RUN \
    # Install Font Awesome.
    curl -sS -L -O ${FONTAWESOME_URL} && \
    unzip font-awesome-${FONTAWESOME_VERSION}.zip && \
    cp -v font-awesome-${FONTAWESOME_VERSION}/fonts/fontawesome-webfont.* /opt/noVNC/app/fonts/ && \
    cp -v font-awesome-${FONTAWESOME_VERSION}/css/font-awesome.min.css /opt/noVNC/app/styles/
RUN \
    # Set version of CSS and JavaScript file URLs.
    sed "s/UNIQUE_VERSION/$(date | md5sum | cut -c1-10)/g" -i /opt/noVNC/index.html
RUN \
    # Generate favicons.
    APP_ICON_URL=https://github.com/jlesage/docker-templates/raw/master/jlesage/images/generic-app-icon.png && \
    install_app_icon.sh --no-tools-install "$APP_ICON_URL"

# Generate default DH params.
FROM --platform=$BUILDPLATFORM alpine:3.15 AS dhparam
RUN apk --no-cache add openssl
RUN echo "Generating default DH parameters (2048 bits)..."
RUN openssl dhparam \
        -out "/tmp/dhparam.pem" \
        2048 \
        > /dev/null 2>&1

# Pull base image.
FROM ${BASEIMAGE}

# Define working directory.
WORKDIR /tmp

# Install system packages.
ARG ALPINE_PKGS
ARG DEBIAN_PKGS
RUN \
    if [ -n "$(which apk)" ]; then \
        add-pkg ${ALPINE_PKGS}; \
    else \
        add-pkg ${DEBIAN_PKGS}; \
    fi && \
    # Remove some unneeded stuff.
    rm -rf /var/cache/fontconfig/*

# Add files.
COPY --link helpers/* /opt/base/bin/
COPY --link rootfs/ /
COPY --link --from=tigervnc /tmp/tigervnc-install/usr/bin/Xvnc /opt/base/bin/
COPY --link --from=tigervnc /tmp/tigervnc-install/usr/bin/vncpasswd /opt/base/bin/
COPY --link --from=tigervnc /tmp/xkb-install/usr/share/X11/xkb /opt/base/share/X11/xkb
COPY --link --from=tigervnc /tmp/xkbcomp-install/usr/bin/xkbcomp /opt/base/bin/
COPY --link --from=openbox /tmp/openbox-install/usr/bin/openbox /opt/base/bin/
COPY --link --from=openbox /tmp/openbox-install/usr/bin/obxprop /opt/base/bin/
COPY --link --from=fontconfig /tmp/fontconfig-install/opt /opt
COPY --link --from=xdpyprobe /tmp/xdpyprobe/xdpyprobe /opt/base/bin/
COPY --link --from=yad /tmp/yad-install/usr/bin/yad /opt/base/bin/
COPY --link --from=nginx /tmp/nginx-install /opt/base/
COPY --link --from=dhparam /tmp/dhparam.pem /defaults/
COPY --link --from=noVNC /opt/noVNC /opt/noVNC

# Set environment variables.
ENV \
    DISPLAY_WIDTH=1920 \
    DISPLAY_HEIGHT=1080 \
    DARK_MODE=0 \
    SECURE_CONNECTION=0 \
    SECURE_CONNECTION_VNC_METHOD=SSL \
    SECURE_CONNECTION_CERTS_CHECK_INTERVAL=60 \
    WEB_LISTENING_PORT=5800 \
    VNC_LISTENING_PORT=5900 \
    VNC_PASSWORD= \
    ENABLE_CJK_FONT=0

# Expose ports.
#   - 5800: VNC web interface
#   - 5900: VNC
EXPOSE 5800 5900

# Metadata.
ARG IMAGE_VERSION=unknown
LABEL \
      org.label-schema.name="baseimage-gui" \
      org.label-schema.description="A minimal docker baseimage to ease creation of X graphical application containers" \
      org.label-schema.version="${IMAGE_VERSION}" \
      org.label-schema.vcs-url="https://github.com/jlesage/docker-baseimage-gui" \
      org.label-schema.schema-version="1.0"
