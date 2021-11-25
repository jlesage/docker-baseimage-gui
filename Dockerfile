#
# baseimage-gui Dockerfile
#
# https://github.com/jlesage/docker-baseimage-gui
#

ARG BASEIMAGE=unknown

# Define the Alpine packages to be installed into the image.
ARG ALPINE_PKGS="\
    # Needed by the X server.
    xkbcomp \
    xkeyboard-config \
    # Font and its config used by the window manager.
    # NOTE: Package automatically pulls font config.
    font-croscore \
    # Needed to generate self-signed certificates
    openssl \
"

# Define the Debian/Ubuntu packages to be installed into the image.
ARG DEBIAN_PKGS="\
    # Needed by the X server.
    x11-xkb-utils \
    xkb-data \
    # Used to determine if nginx is ready.
    netcat \
    # Font and its config used by the window manager.
    # NOTE: Package automatically pulls a font.
    fontconfig-config \
    # For ifconfig
    net-tools \
    # Needed to generate self-signed certificates
    openssl \
"

# Get Dockerfile cross-compilation helpers.
FROM --platform=$BUILDPLATFORM tonistiigi/xx AS xx

# Build UPX.
# NOTE: The latest official release of UPX (version 3.96) produces binaries that
# crash on ARM.  We need to manually compile it with all latest fixes.
FROM --platform=$BUILDPLATFORM alpine:3.14 AS upx
RUN apk --no-cache add build-base git bash perl ucl-dev zlib-dev zlib-static && \
    git clone --recurse-submodules https://github.com/upx/upx.git /tmp/upx && \
    git -C /tmp/upx checkout f75ad8b && \
    make LDFLAGS=-static CXXFLAGS_OPTIMIZE= -C /tmp/upx -j$(nproc) all

# Build TigerVNC server.
FROM --platform=$BUILDPLATFORM alpine:3.14 AS tigervnc
ARG TARGETPLATFORM
COPY --from=xx / /
COPY src/tigervnc/build.sh /tmp/build-tigervnc.sh
RUN /tmp/build-tigervnc.sh
RUN xx-verify --static /tmp/tigervnc-install/usr/bin/Xvnc
RUN xx-verify --static /tmp/tigervnc-install/usr/bin/vncpasswd
COPY --from=upx /tmp/upx/src/upx.out /usr/bin/upx
RUN upx /tmp/tigervnc-install/usr/bin/Xvnc
RUN upx /tmp/tigervnc-install/usr/bin/vncpasswd

# Build JWM
FROM --platform=$BUILDPLATFORM alpine:3.14 AS jwm
ARG TARGETPLATFORM
COPY --from=xx / /
COPY src/jwm/build.sh /tmp/build-jwm.sh
RUN /tmp/build-jwm.sh
RUN xx-verify --static /tmp/jwm-install/usr/bin/jwm
COPY --from=upx /tmp/upx/src/upx.out /usr/bin/upx
RUN upx /tmp/jwm-install/usr/bin/jwm

# Build xdpyprobe.
FROM --platform=$BUILDPLATFORM alpine:3.14 AS xdpyprobe
ARG TARGETPLATFORM
COPY --from=xx / /
COPY src/xdpyprobe /tmp/xdpyprobe
RUN apk --no-cache add make clang
RUN xx-apk --no-cache add gcc musl-dev libx11-dev libx11-static libxcb-static
RUN CC=xx-clang \
    make -C /tmp/xdpyprobe
RUN xx-verify --static /tmp/xdpyprobe/xdpyprobe
COPY --from=upx /tmp/upx/src/upx.out /usr/bin/upx
RUN upx /tmp/xdpyprobe/xdpyprobe

# Build xprop.
FROM --platform=$BUILDPLATFORM alpine:3.14 AS xprop
ARG TARGETPLATFORM
COPY --from=xx / /
COPY src/xprop/build.sh /tmp/build-xprop.sh
RUN /tmp/build-xprop.sh
RUN xx-verify --static /tmp/xprop-install/usr/bin/xprop
COPY --from=upx /tmp/upx/src/upx.out /usr/bin/upx
RUN upx /tmp/xprop-install/usr/bin/xprop

# Build Nginx.
FROM --platform=$BUILDPLATFORM alpine:3.14 AS nginx
ARG TARGETPLATFORM
COPY --from=xx / /
COPY src/nginx/build.sh /tmp/build-nginx.sh
RUN /tmp/build-nginx.sh
RUN xx-verify --static /tmp/nginx-install/usr/sbin/nginx
COPY --from=upx /tmp/upx/src/upx.out /usr/bin/upx
RUN upx /tmp/nginx-install//usr/sbin/nginx

# Build noVNC.
FROM  --platform=$BUILDPLATFORM alpine:3.14 AS novnc
ARG NOVNC_VERSION=fa559b3
ARG BOOTSTRAP_VERSION=3.3.7
ARG FONTAWESOME_VERSION=4.7.0
ARG JQUERY_VERSION=3.2.1
ARG JQUERY_UI_TOUCH_PUNCH_VERSION=4bc0091
ARG NOVNC_URL=https://github.com/jlesage/novnc/archive/${NOVNC_VERSION}.tar.gz
ARG BOOTSTRAP_URL=https://github.com/twbs/bootstrap/releases/download/v${BOOTSTRAP_VERSION}/bootstrap-${BOOTSTRAP_VERSION}-dist.zip
ARG FONTAWESOME_URL=https://fontawesome.com/v${FONTAWESOME_VERSION}/assets/font-awesome-${FONTAWESOME_VERSION}.zip
ARG JQUERY_URL=https://code.jquery.com/jquery-${JQUERY_VERSION}.min.js
ARG JQUERY_UI_TOUCH_PUNCH_URL=https://raw.github.com/furf/jquery-ui-touch-punch/${JQUERY_UI_TOUCH_PUNCH_VERSION}/jquery.ui.touch-punch.min.js
WORKDIR /tmp
COPY rootfs/opt /opt
RUN \
    apk --no-cache add curl npm && \
    npm install -g uglify-js source-map && \
    # Install noVNC core files.
    mkdir noVNC && \
    curl -sS -L ${NOVNC_URL} | tar -xz --strip 1 -C noVNC && \
    mkdir -p /opt/novnc/include && \
    mkdir -p /opt/novnc/js && \
    mkdir -p /opt/novnc/css && \
    NOVNC_CORE="\
        noVNC/include/util.js \
        noVNC/include/webutil.js \
        noVNC/include/base64.js \
        noVNC/include/websock.js \
        noVNC/include/des.js \
        noVNC/include/keysymdef.js \
        noVNC/include/keyboard.js \
        noVNC/include/input.js \
        noVNC/include/display.js \
        noVNC/include/rfb.js \
        noVNC/include/keysym.js \
        noVNC/include/inflator.js \
    " && \
    cp -v $NOVNC_CORE /opt/novnc/include/ && \
    # Minify noVNC core JS files
    uglifyjs \
        --compress --mangle --source-map \
        --output /opt/novnc/js/novnc-core.min.js -- $NOVNC_CORE && \
    sed 's|"noVNC/|"/|g' -i /opt/novnc/js/novnc-core.min.js.map && \
    echo -e "\n//# sourceMappingURL=/js/novnc-core.min.js.map" >> /opt/novnc/js/novnc-core.min.js && \
    # Install Bootstrap
    curl -sS -L -O ${BOOTSTRAP_URL} && \
    unzip bootstrap-${BOOTSTRAP_VERSION}-dist.zip && \
    cp -v bootstrap-${BOOTSTRAP_VERSION}-dist/css/bootstrap.min.css /opt/novnc/css/ && \
    cp -v bootstrap-${BOOTSTRAP_VERSION}-dist/js/bootstrap.min.js /opt/novnc/js/ && \
    # Install Font Awesome
    curl -sS -L -O ${FONTAWESOME_URL} && \
    unzip font-awesome-${FONTAWESOME_VERSION}.zip && \
    cp -vr font-awesome-${FONTAWESOME_VERSION}/fonts /opt/novnc/ && \
    cp -v font-awesome-${FONTAWESOME_VERSION}/css/font-awesome.min.css /opt/novnc/css/ && \
    # Install JQuery
    curl -sS -L -o /opt/novnc/js/jquery.min.js ${JQUERY_URL} && \
    curl -sS -L -o /opt/novnc/js/jquery.ui.touch-punch.min.js ${JQUERY_UI_TOUCH_PUNCH_URL} && \
    # Minify noVNC UI JS files.
    NOVNC_UI="\
        /opt/novnc/app/modulemgr.js \
        /opt/novnc/app/ui.js \
        /opt/novnc/app/modules/hideablenavbar.js \
        /opt/novnc/app/modules/dynamicappname.js \
        /opt/novnc/app/modules/password.js \
        /opt/novnc/app/modules/clipboard.js \
        /opt/novnc/app/modules/autoscaling.js \
        /opt/novnc/app/modules/clipping.js \
        /opt/novnc/app/modules/viewportdrag.js \
        /opt/novnc/app/modules/fullscreen.js \
        /opt/novnc/app/modules/virtualkeyboard.js \
        /opt/novnc/app/modules/rightclick.js \
    " && \
    uglifyjs \
        --compress --mangle --source-map \
        --output /opt/novnc/js/novnc-ui.min.js -- $NOVNC_UI && \
    echo -e "\n//# sourceMappingURL=/js/novnc-ui.min.js.map" >> /opt/novnc/js/novnc-ui.min.js && \
    sed 's/\/opt\/novnc//g' -i /opt/novnc/js/novnc-ui.min.js.map && \
    # Set version of CSS and JavaScript file URLs.
    sed "s/UNIQUE_VERSION/$(date | md5sum | cut -c1-10)/g" -i /opt/novnc/index.vnc

# Generate favicons.
FROM --platform=$BUILDPLATFORM alpine:3.14 AS favicons
COPY helpers/* /usr/bin/
COPY rootfs/opt/novnc/index.vnc /tmp/index.vnc
RUN apk --no-cache add curl sed jq
RUN \
    APP_ICON_URL=https://github.com/jlesage/docker-templates/raw/master/jlesage/images/generic-app-icon.png && \
    install_app_icon.sh "$APP_ICON_URL"  \
        --icons-dir /tmp/icons \
        --html-file /tmp/index.vnc \
        --no-tools-install

# Generate default DH params.
FROM --platform=$BUILDPLATFORM alpine:3.14 AS dhparam
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
    # Disable unsupported keysym (related to Wayland).
    find /usr/share/X11/xkb -type f -exec sed '/.* key .*XF86.*/s/^/\/\//' -i {} ';' && \
    # Remove some unneeded stuff.
    rm -rf /var/cache/fontconfig/*

## Install packages.
#RUN \
#    add-pkg \
#        # Needed by the X server.
#        xkbcomp \
#        xkeyboard-config \
#        # Used to determine when the X server is ready
##        xdpyinfo \
#        # Openbox window manager
#        openbox \
#        xsetroot \
#        # Font
#        font-croscore \
#        # Needed to generate self-signed certificates
#        openssl \
#        && \
#    # Disable unsupported keysym (related to Wayland).
#    # TODO: Install our own compiled xkeyboard-config ??
#    find /usr/share/X11/xkb -type f -exec sed '/.* key .*XF86.*/s/^/\/\//' -i {} ';' && \
#    # Remove some unneeded stuff.
#    rm -rf /var/cache/fontconfig/*

# Add files.
COPY helpers/* /usr/bin/
COPY rootfs/ /
COPY --from=tigervnc /tmp/tigervnc-install/usr/bin/Xvnc /usr/bin/
COPY --from=tigervnc /tmp/tigervnc-install/usr/bin/vncpasswd /usr/bin/
COPY --from=jwm /tmp/jwm-install/usr/bin/jwm /usr/bin/
COPY --from=xdpyprobe /tmp/xdpyprobe/xdpyprobe /usr/bin/
COPY --from=xprop /tmp/xprop-install/usr/bin/xprop /usr/bin/
COPY --from=nginx /tmp/nginx-install /
COPY --from=dhparam /tmp/dhparam.pem /defaults/
COPY --from=novnc /opt/novnc /opt/novnc
COPY --from=favicons /tmp/icons /opt/novnc/images/icons
COPY --from=favicons /tmp/index.vnc /opt/novnc/index.vnc

# Set environment variables.
ENV \
    DISPLAY_WIDTH=1280 \
    DISPLAY_HEIGHT=768

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
