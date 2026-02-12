# syntax=docker/dockerfile:1.4
#
# baseimage-gui Dockerfile
#
# https://github.com/jlesage/docker-baseimage-gui
#

ARG BASEIMAGE=unknown
ARG BASEIMAGE_COMMON=unknown

# Define the Alpine packages to be installed into the image.
ARG ALPINE_PKGS="\
    # Needed to generate self-signed certificates.
    openssl \
    # Used to determine if nginx is ready.
    netcat-openbsd \
"

# Define the Debian/Ubuntu packages to be installed into the image.
ARG DEBIAN_PKGS="\
    # Needed to generate self-signed certificates.
    openssl \
    # Used to determine if nginx is ready.
    netcat-openbsd \
    # For ifconfig
    net-tools \
"

# Common stuff of the baseimage.
FROM ${BASEIMAGE_COMMON} AS baseimage-common

# Pull base image.
FROM ${BASEIMAGE}

# Define working directory.
WORKDIR /tmp

# Install system packages.
ARG ALPINE_PKGS
ARG DEBIAN_PKGS
RUN \
    case "$(awk -F= '/^ID=/ {print $2}' /etc/os-release)" in \
        alpine) \
            /opt/base/bin/add-pkg ${ALPINE_PKGS}; \
            ;; \
        debian|ubuntu) \
            /opt/base/bin/add-pkg ${DEBIAN_PKGS}; \
            ;; \
        *) \
            echo "ERROR: unknown os ID '$(awk -F= '/^ID=/ {print $2}' /etc/os-release)'"; \
            exit 1; \
            ;; \
    esac && \
    # Remove some unneeded stuff.
    rm -rf /var/cache/fontconfig/*

# Install common software.
COPY --link --from=baseimage-common / /

# Set environment variables.
ENV \
    DISPLAY_WIDTH=1920 \
    DISPLAY_HEIGHT=1080 \
    DARK_MODE=0 \
    SECURE_CONNECTION=0 \
    SECURE_CONNECTION_VNC_METHOD=SSL \
    SECURE_CONNECTION_CERTS_CHECK_INTERVAL=60 \
    WEB_LOCALHOST_ONLY=0 \
    VNC_LOCALHOST_ONLY=0 \
    WEB_LISTENING_PORT=5800 \
    VNC_LISTENING_PORT=5900 \
    VNC_PASSWORD= \
    ENABLE_CJK_FONT=0 \
    WEB_AUDIO=0 \
    WEB_AUTHENTICATION=0 \
    WEB_AUTHENTICATION_TOKEN_VALIDITY_TIME=24 \
    WEB_AUTHENTICATION_USERNAME= \
    WEB_AUTHENTICATION_PASSWORD= \
    WEB_FILE_MANAGER=0 \
    WEB_FILE_MANAGER_ALLOWED_PATHS=AUTO \
    WEB_FILE_MANAGER_DENIED_PATHS= \
    WEB_NOTIFICATION=0 \
    WEB_TERMINAL=0

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
