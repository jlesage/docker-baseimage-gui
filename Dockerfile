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
# NOTE: The latest official release of UPX (version 3.96) produces binaries that
# crash on ARM.  We need to manually compile it with all latest fixes.
FROM --platform=$BUILDPLATFORM alpine:3.15 AS upx
RUN apk --no-cache add build-base git bash perl ucl-dev zlib-dev zlib-static && \
    git clone --recurse-submodules https://github.com/upx/upx.git /tmp/upx && \
    git -C /tmp/upx checkout f75ad8b && \
    make LDFLAGS=-static CXXFLAGS_OPTIMIZE= -C /tmp/upx -j$(nproc) all

# Build TigerVNC server.
FROM --platform=$BUILDPLATFORM alpine:3.15 AS tigervnc
ARG TARGETPLATFORM
COPY --from=xx / /
COPY src/tigervnc/build.sh /tmp/build-tigervnc.sh
RUN /tmp/build-tigervnc.sh
RUN xx-verify --static /tmp/tigervnc-install/usr/bin/Xvnc
RUN xx-verify --static /tmp/tigervnc-install/usr/bin/vncpasswd
COPY --from=upx /tmp/upx/src/upx.out /usr/bin/upx
RUN upx /tmp/tigervnc-install/usr/bin/Xvnc
RUN upx /tmp/tigervnc-install/usr/bin/vncpasswd

# Build XKeyboard.
FROM --platform=$BUILDPLATFORM alpine:3.15 AS xkb
ARG TARGETPLATFORM
COPY --from=xx / /
COPY src/xkb/build.sh /tmp/build-xkb.sh
RUN /tmp/build-xkb.sh
RUN xx-verify --static /tmp/xkbcomp-install/usr/bin/xkbcomp
COPY --from=upx /tmp/upx/src/upx.out /usr/bin/upx
RUN upx /tmp/xkbcomp-install/usr/bin/xkbcomp

# Build JWM.
FROM --platform=$BUILDPLATFORM alpine:3.15 AS jwm
ARG TARGETPLATFORM
COPY --from=xx / /
COPY src/jwm/build.sh /tmp/build-jwm.sh
RUN /tmp/build-jwm.sh
RUN xx-verify --static /tmp/jwm-install/usr/bin/jwm
COPY --from=upx /tmp/upx/src/upx.out /usr/bin/upx
RUN upx /tmp/jwm-install/usr/bin/jwm

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
COPY --from=upx /tmp/upx/src/upx.out /usr/bin/upx
RUN upx /tmp/xdpyprobe/xdpyprobe

# Build xprop.
FROM --platform=$BUILDPLATFORM alpine:3.15 AS xprop
ARG TARGETPLATFORM
COPY --from=xx / /
COPY src/xprop/build.sh /tmp/build-xprop.sh
RUN /tmp/build-xprop.sh
RUN xx-verify --static /tmp/xprop-install/usr/bin/xprop
COPY --from=upx /tmp/upx/src/upx.out /usr/bin/upx
RUN upx /tmp/xprop-install/usr/bin/xprop

# Build yad.
FROM --platform=$BUILDPLATFORM alpine:3.15 AS yad
ARG TARGETPLATFORM
COPY --from=xx / /
COPY src/yad/build.sh /tmp/build-yad.sh
RUN /tmp/build-yad.sh
RUN xx-verify --static /tmp/yad-install/usr/bin/yad
COPY --from=upx /tmp/upx/src/upx.out /usr/bin/upx
RUN upx /tmp/yad-install/usr/bin/yad

# Build Nginx.
FROM --platform=$BUILDPLATFORM alpine:3.15 AS nginx
ARG TARGETPLATFORM
COPY --from=xx / /
COPY src/nginx/build.sh /tmp/build-nginx.sh
RUN /tmp/build-nginx.sh
RUN xx-verify --static /tmp/nginx-install/usr/sbin/nginx
COPY --from=upx /tmp/upx/src/upx.out /usr/bin/upx
RUN upx /tmp/nginx-install//usr/sbin/nginx

# Build noVNC.
FROM --platform=$BUILDPLATFORM alpine:3.15 AS noVNC
ARG NOVNC_VERSION=1.3.0
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

# Build noVNC.
FROM --platform=$BUILDPLATFORM alpine:3.15 AS novnc
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
FROM --platform=$BUILDPLATFORM alpine:3.15 AS favicons
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
COPY helpers/* /usr/bin/
COPY rootfs/ /
COPY --from=tigervnc /tmp/tigervnc-install/usr/bin/Xvnc /opt/tigervnc/bin/
COPY --from=tigervnc /tmp/tigervnc-install/usr/bin/vncpasswd /usr/tigervnc/bin/
COPY --from=tigervnc /tmp/xkb-install/usr/share/X11/xkb /opt/tigervnc/xkb
COPY --from=tigervnc /tmp/xkbcomp-install/usr/bin/xkbcomp /opt/tigervnc/xkb/
COPY --from=jwm /tmp/jwm-install/usr/bin/jwm /opt/jwm/bin/jwm
COPY --from=jwm /opt/jwm/fonts /opt/jwm/fonts
COPY --from=jwm /tmp/fontconfig-install/opt/jwm/fontconfig /opt/jwm/fontconfig
COPY --from=xdpyprobe /tmp/xdpyprobe/xdpyprobe /usr/bin/
COPY --from=xprop /tmp/xprop-install/usr/bin/xprop /usr/bin/
COPY --from=yad /tmp/yad-install/usr/bin/yad /usr/bin/
COPY --from=nginx /tmp/nginx-install /
COPY --from=dhparam /tmp/dhparam.pem /defaults/
COPY --from=noVNC /opt/noVNC /opt/noVNC

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
