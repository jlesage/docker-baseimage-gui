# A minimal docker baseimage to ease creation of X graphical application containers
[![Docker Automated build](https://img.shields.io/docker/automated/jlesage/baseimage-gui.svg)](https://hub.docker.com/r/jlesage/baseimage-gui/) [![Build Status](https://travis-ci.org/jlesage/docker-baseimage-gui.svg?branch=master)](https://travis-ci.org/jlesage/docker-baseimage-gui)

This is a docker baseimage that can be used to create containers able to run any
X application on a headless server very easily.  The application's GUI is
accessed through a modern web browser (no installation or configuration needed
on the client side) or via any VNC client.

## Table of Content

   * [A minimal docker baseimage to ease creation of X graphical application containers](#a-minimal-docker-baseimage-to-ease-creation-of-x-graphical-application-containers)
      * [Table of Content](#table-of-content)
      * [Images](#images)
         * [Content](#content)
         * [Versioning](#versioning)
         * [Tags](#tags)
      * [Getting started](#getting-started)
      * [Environment Variables](#environment-variables)
      * [Config Directory](#config-directory)
      * [Ports](#ports)
      * [User/Group IDs](#usergroup-ids)
      * [Locales](#locales)
      * [Accessing the GUI](#accessing-the-gui)
      * [Security](#security)
         * [SSVNC](#ssvnc)
         * [Certificates](#certificates)
         * [VNC Password](#vnc-password)
         * [DH Parameters](#dh-parameters)
      * [Building A Container](#building-a-container)
         * [Selecting Baseimage Tag](#selecting-baseimage-tag)
         * [Referencing Linux User/Group](#referencing-linux-usergroup)
         * [Default Configuration Files](#default-configuration-files)
         * [Adding/Removing Packages](#addingremoving-packages)
         * [Modifying Files With Sed](#modifying-files-with-sed)
         * [Modifying Baseimage Content](#modifying-baseimage-content)
         * [Application's Data](#applications-data)
         * [$HOME Environment Variable](#home-environment-variable)
         * [Service Dependencies](#service-dependencies)
         * [Service Readiness](#service-readiness)
         * [Log Monitor](#log-monitor)
            * [Monitored Files](#monitored-files)
            * [Notification Definition](#notification-definition)
            * [Notification Backend](#notification-backend)
         * [Application Icon](#application-icon)
         * [Maximizing Only the Main Window](#maximizing-only-the-main-window)
         * [S6 Overlay Documentation](#s6-overlay-documentation)

## Images
Different docker images are available:

| Base distribution  | Tag              | Size |
|--------------------|------------------|------|
| [Alpine 3.10]      | alpine-3.10      | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:alpine-3.10.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:alpine-3.10 "Get your own image badge on microbadger.com") |
| [Alpine 3.11]      | alpine-3.11      | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:alpine-3.11.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:alpine-3.11 "Get your own image badge on microbadger.com") |
| [Alpine 3.12]      | alpine-3.12      | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:alpine-3.12.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:alpine-3.12 "Get your own image badge on microbadger.com") |
| [Alpine 3.13]      | alpine-3.13      | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:alpine-3.13.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:alpine-3.13 "Get your own image badge on microbadger.com") |
| [Alpine 3.14]      | alpine-3.14      | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:alpine-3.14.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:alpine-3.14 "Get your own image badge on microbadger.com") |
| [Alpine 3.15]      | alpine-3.15      | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:alpine-3.15.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:alpine-3.15 "Get your own image badge on microbadger.com") |
| [Alpine 3.5]       | alpine-3.5-glibc | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:alpine-3.5-glibc.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:alpine-3.5-glibc "Get your own image badge on microbadger.com") |
| [Alpine 3.6]       | alpine-3.6-glibc | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:alpine-3.6-glibc.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:alpine-3.6-glibc "Get your own image badge on microbadger.com") |
| [Alpine 3.7]       | alpine-3.7-glibc | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:alpine-3.7-glibc.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:alpine-3.7-glibc "Get your own image badge on microbadger.com") |
| [Alpine 3.8]       | alpine-3.8-glibc | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:alpine-3.8-glibc.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:alpine-3.8-glibc "Get your own image badge on microbadger.com") |
| [Alpine 3.9]       | alpine-3.9-glibc | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:alpine-3.9-glibc.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:alpine-3.9-glibc "Get your own image badge on microbadger.com") |
| [Alpine 3.10]       | alpine-3.10-glibc | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:alpine-3.10-glibc.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:alpine-3.10-glibc "Get your own image badge on microbadger.com") |
| [Alpine 3.11]       | alpine-3.11-glibc | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:alpine-3.11-glibc.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:alpine-3.11-glibc "Get your own image badge on microbadger.com") |
| [Alpine 3.12]       | alpine-3.12-glibc | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:alpine-3.12-glibc.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:alpine-3.12-glibc "Get your own image badge on microbadger.com") |
| [Alpine 3.13]       | alpine-3.13-glibc | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:alpine-3.13-glibc.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:alpine-3.13-glibc "Get your own image badge on microbadger.com") |
| [Alpine 3.14]       | alpine-3.14-glibc | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:alpine-3.14-glibc.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:alpine-3.14-glibc "Get your own image badge on microbadger.com") |
| [Alpine 3.15]       | alpine-3.15-glibc | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:alpine-3.15-glibc.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:alpine-3.15-glibc "Get your own image badge on microbadger.com") |
| [Debian 8]         | debian-8         | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:debian-8.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:debian-8/ "Get your own image badge on microbadger.com") |
| [Debian 9]         | debian-9         | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:debian-9.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:debian-9/ "Get your own image badge on microbadger.com") |
| [Debian 10]        | debian-10        | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:debian-10.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:debian-10/ "Get your own image badge on microbadger.com") |
| [Debian 11]        | debian-11        | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:debian-11.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:debian-11/ "Get your own image badge on microbadger.com") |
| [Ubuntu 16.04 LTS] | ubuntu-16.04     | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:ubuntu-16.04.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:ubuntu-16.04 "Get your own image badge on microbadger.com") |
| [Ubuntu 18.04 LTS] | ubuntu-18.04     | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:ubuntu-18.04.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:ubuntu-18.04 "Get your own image badge on microbadger.com") |
| [Ubuntu 20.04 LTS] | ubuntu-20.04     | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:ubuntu-20.04.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:ubuntu-20.04 "Get your own image badge on microbadger.com") |

[Alpine 3.10]: https://alpinelinux.org
[Alpine 3.11]: https://alpinelinux.org
[Alpine 3.12]: https://alpinelinux.org
[Alpine 3.13]: https://alpinelinux.org
[Alpine 3.14]: https://alpinelinux.org
[Alpine 3.15]: https://alpinelinux.org
[Debian 8]: https://www.debian.org/releases/jessie/
[Debian 9]: https://www.debian.org/releases/stretch/
[Debian 10]: https://www.debian.org/releases/buster/
[Debian 11]: https://www.debian.org/releases/bullseye/
[Ubuntu 16.04 LTS]: http://releases.ubuntu.com/16.04/
[Ubuntu 18.04 LTS]: http://releases.ubuntu.com/18.04/
[Ubuntu 20.04 LTS]: http://releases.ubuntu.com/20.04/

Due to its size, an `Alpine` image is recommended.  However, it may be harder
to integrate your application (especially third party ones without source code),
because:
 1. Packages repository may not be as complete as `Ubuntu`/`Debian`.
 2. Third party applications may not support `Alpine`.
 3. The `Alpine` distribution uses the [musl] C standard library instead of
 GNU C library ([glibc]).

Note that using an `Alpine` image with glibc integrated (`alpine-3.5-glibc`
tag) may ease integration of applications.

The next choice is to use a `Debian` image.  It provides a great compatibility
and its size is smaller than the `Ubuntu` one.  Finally, if for any reason you
prefer an `Ubuntu` image, stable `LTS` versions are provided.

[musl]: https://www.musl-libc.org/
[glibc]: https://www.gnu.org/software/libc/

### Content
Here are the main components of the baseimage:
  * [S6-overlay], a process supervisor for containers.
  * [x11vnc], a X11 VNC server.
  * [xvfb], a X virtual framebuffer display server.
  * [openbox], a windows manager.
  * [noVNC], a HTML5 VNC client.
  * [NGINX], a high-performance HTTP server.
  * [stunnel], a proxy encrypting arbitrary TCP connections with SSL/TLS.
  * Useful tools to ease container building.
  * Environment to better support dockerized applications.

[S6-overlay]: https://github.com/just-containers/s6-overlay
[x11vnc]: http://www.karlrunge.com/x11vnc/
[xvfb]: http://www.x.org/releases/X11R7.6/doc/man/man1/Xvfb.1.xhtml
[openbox]: http://openbox.org
[noVNC]: https://github.com/novnc/noVNC
[NGINX]: https://www.nginx.com
[stunnel]: https://www.stunnel.org

### Versioning

Images are versioned.  Version number is in the form `MAJOR.MINOR.PATCH`, where
an increment of the:
  - MAJOR version indicates that a backwards-incompatible change has been done.
  - MINOR version indicates that functionality has been added in a backwards-compatible manner.
  - PATCH version indicates that a bug fix has been done in a backwards-compatible manner.

### Tags

For each distribution-specific image, multiple tags are available:

| Tag | Description |
|-----|-------------|
| distro-vX.Y.Z | Exact version of the image. |
| distro-vX.Y   | Latest version of a specific minor version of the image. |
| distro-vX     | Latest version of a specific major version of the image. |
| distro        | Latest version of the image. |

## Getting started
The `Dockerfile` for your application can be very simple, as only three things
are required:

  * Instructions to install the application.
  * A script that starts the application (stored at `/startapp.sh` in
    container).
  * The name of the application.

Here is an example of a docker file that would be used to run the `xterm`
terminal.

In ``Dockerfile``:
```
# Pull base image.
FROM jlesage/baseimage-gui:alpine-3.6

# Install xterm.
RUN add-pkg xterm

# Copy the start script.
COPY startapp.sh /startapp.sh

# Set the name of the application.
ENV APP_NAME="Xterm"

```

In `startapp.sh`:
```
#!/bin/sh
exec /usr/bin/xterm
```

Then, build your docker image:

    docker build -t docker-xterm .

And run it:

    docker run --rm -p 5800:5800 -p 5900:5900 docker-xterm

You should be able to access the xterm GUI by opening in a web browser:

`http://[HOST IP ADDR]:5800`

## Environment Variables

Some environment variables can be set to customize the behavior of the container
and its application.  The following list give more details about them.

Environment variables can be set directly in your `Dockerfile` via the `ENV`
instruction or dynamically by adding one or more arguments `-e "<VAR>=<VALUE>"`
to the `docker run` command.

| Variable       | Description                                  | Default |
|----------------|----------------------------------------------|---------|
|`APP_NAME`| Name of the application. | `DockerApp` |
|`USER_ID`| ID of the user the application runs as.  See [User/Group IDs](#usergroup-ids) to better understand when this should be set. | `1000` |
|`GROUP_ID`| ID of the group the application runs as.  See [User/Group IDs](#usergroup-ids) to better understand when this should be set. | `1000` |
|`SUP_GROUP_IDS`| Comma-separated list of supplementary group IDs of the application. | (unset) |
|`UMASK`| Mask that controls how file permissions are set for newly created files. The value of the mask is in octal notation.  By default, this variable is not set and the default umask of `022` is used, meaning that newly created files are readable by everyone, but only writable by the owner. See the following online umask calculator: http://wintelguy.com/umask-calc.pl | (unset) |
|`TZ`| [TimeZone] of the container.  Timezone can also be set by mapping `/etc/localtime` between the host and the container. | `Etc/UTC` |
|`KEEP_APP_RUNNING`| When set to `1`, the application will be automatically restarted if it crashes or if a user quits it. | `0` |
|`APP_NICENESS`| Priority at which the application should run.  A niceness value of -20 is the highest priority and 19 is the lowest priority.  By default, niceness is not set, meaning that the default niceness of 0 is used.  **NOTE**: A negative niceness (priority increase) requires additional permissions.  In this case, the container should be run with the docker option `--cap-add=SYS_NICE`. | (unset) |
|`TAKE_CONFIG_OWNERSHIP`| When set to `1`, owner and group of `/config` (including all its files and subfolders) are automatically set during container startup to `USER_ID` and `GROUP_ID` respectively. | `1` |
|`CLEAN_TMP_DIR`| When set to `1`, all files in the `/tmp` directory are deleted during the container startup. | `1` |
|`DISPLAY_WIDTH`| Width (in pixels) of the application's window. | `1280` |
|`DISPLAY_HEIGHT`| Height (in pixels) of the application's window. | `768` |
|`SECURE_CONNECTION`| When set to `1`, an encrypted connection is used to access the application's GUI (either via a web browser or VNC client).  See the [Security](#security) section for more details. | `0` |
|`VNC_PASSWORD`| Password needed to connect to the application's GUI.  See the [VNC Password](#vnc-password) section for more details. | (unset) |
|`X11VNC_EXTRA_OPTS`| Extra options to pass to the x11vnc server running in the Docker container.  **WARNING**: For advanced users. Do not use unless you know what you are doing. | (unset) |
|`ENABLE_CJK_FONT`| When set to `1`, open-source computer font `WenQuanYi Zen Hei` is installed.  This font contains a large range of Chinese/Japanese/Korean characters. | `0` |

## Config Directory
Inside the container, the application's configuration should be stored in the
`/config` directory.

This directory is also used to store the VNC password.  See the
[VNC Pasword](#vnc-password) section for more details.

**NOTE**: By default, during the container startup, the user which runs the
application (i.e. user defined by `USER_ID`) will claim ownership of the
entire content of this directory.  This behavior can be changed via the
`TAKE_CONFIG_OWNERSHIP` environment variable.  See the
[Environment Variables](#environment-variables) section for more details.

## Ports

Here is the list of ports used by container.  They can be mapped to the host
via the `-p <HOST_PORT>:<CONTAINER_PORT>` parameter.  The port number inside the
container cannot be changed, but you are free to use any port on the host side.

| Port | Mapping to host | Description |
|------|-----------------|-------------|
| 5800 | Mandatory | Port used to access the application's GUI via the web interface. |
| 5900 | Optional | Port used to access the application's GUI via the VNC protocol.  Optional if no VNC client is used. |

## User/Group IDs

When using data volumes (`-v` flags), permissions issues can occur between the
host and the container.  For example, the user within the container may not
exists on the host.  This could prevent the host from properly accessing files
and folders on the shared volume.

To avoid any problem, you can specify the user the application should run as.

This is done by passing the user ID and group ID to the container via the
`USER_ID` and `GROUP_ID` environment variables.

To find the right IDs to use, issue the following command on the host, with the
user owning the data volume on the host:

    id <username>

Which gives an output like this one:
```
uid=1000(myuser) gid=1000(myuser) groups=1000(myuser),4(adm),24(cdrom),27(sudo),46(plugdev),113(lpadmin)
```

The value of `uid` (user ID) and `gid` (group ID) are the ones that you should
be given the container.

## Locales
The default locale of the container is set to `POSIX`.  If this cause issues
with your application, the proper locale can be set via your `Dockerfile`, by adding these two lines:
```
ENV LANG=en_US.UTF-8
RUN locale-gen en_CA.UTF-8
```

**NOTE**: Locales are not supported by `musl` C standard library on `Alpine`.
See:
  * http://wiki.musl-libc.org/wiki/Open_Issues#C_locale_conformance
  * https://github.com/gliderlabs/docker-alpine/issues/144

## Accessing the GUI

Assuming that container's ports are mapped to the same host's ports, the
graphical interface of the application can be accessed via:

  * A web browser:
```
http://<HOST IP ADDR>:5800
```

  * Any VNC client:
```
<HOST IP ADDR>:5900
```

## Security

By default, access to the application's GUI is done over an unencrypted
connection (HTTP or VNC).

Secure connection can be enabled via the `SECURE_CONNECTION` environment
variable.  See the [Environment Variables](#environment-variables) section for
more details on how to set an environment variable.

When enabled, application's GUI is performed over an HTTPs connection when
accessed with a browser.  All HTTP accesses are automatically redirected to
HTTPs.

When using a VNC client, the VNC connection is performed over SSL.  Note that
few VNC clients support this method.  [SSVNC] is one of them.

### SSVNC

[SSVNC] is a VNC viewer that adds encryption security to VNC connections.

While the Linux version of [SSVNC] works well, the Windows version has some
issues.  At the time of writing, the latest version `1.0.30` is not functional,
as a connection fails with the following error:
```
ReadExact: Socket error while reading
```
However, for your convienence, an unoffical and working version is provided
here:

https://github.com/jlesage/docker-baseimage-gui/raw/master/tools/ssvnc_windows_only-1.0.30-r1.zip

The only difference with the offical package is that the bundled version of
`stunnel` has been upgraded to version `5.49`, which fixes the connection
problems.

### Certificates

Here are the certificate files needed by the container.  By default, when they
are missing, self-signed certificates are generated and used.  All files have
PEM encoded, x509 certificates.

| Container Path                  | Purpose                    | Content |
|---------------------------------|----------------------------|---------|
|`/config/certs/vnc-server.pem`   |VNC connection encryption.  |VNC server's private key and certificate, bundled with any root and intermediate certificates.|
|`/config/certs/web-privkey.pem`  |HTTPs connection encryption.|Web server's private key.|
|`/config/certs/web-fullchain.pem`|HTTPs connection encryption.|Web server's certificate, bundled with any root and intermediate certificates.|

**NOTE**: To prevent any certificate validity warnings/errors from the browser
or VNC client, make sure to supply your own valid certificates.

**NOTE**: Certificate files are monitored and relevant daemons are automatically
restarted when changes are detected.

### VNC Password

To restrict access to your application, a password can be specified.  This can
be done via two methods:
  * By using the `VNC_PASSWORD` environment variable.
  * By creating a `.vncpass_clear` file at the root of the `/config` volume.
    This file should contains the password in clear-text.  During the container
    startup, content of the file is obfuscated and moved to `.vncpass`.

The level of security provided by the VNC password depends on two things:
  * The type of communication channel (encrypted/unencrypted).
  * How secure access to the host is.

When using a VNC password, it is highly desirable to enable the secure
connection to prevent sending the password in clear over an unencrypted channel.

Access to the host by unexpected users with sufficient privileges can be
dangerous as they can retrieve the password with the following methods:
  * By looking at the `VNC_PASSWORD` environment variable value via the
    `docker inspect` command.  By defaut, the `docker` command can be run only
    by the root user.  However, it is possible to configure the system to allow
    the `docker` command to be run by any users part of a specific group.
  * By decrypting the `/config/.vncpass` file.  This requires the user to have
    the appropriate permission to read the file:  it has to be root or be the
    user defined by the `USER_ID` environment variable.  Also, to be able to
    retrieve the correct decryption key, one needs to know that the content of
    the file was generated by `x11vnc`.

### DH Parameters

Diffie-Hellman (DH) parameters define how the [DH key-exchange] is performed.
More details about this algorithm can be found on the [OpenSSL Wiki].

DH Parameters are saved into the PEM encoded file located inside the container
at `/config/certs/dhparam.pem`.  By default, when this file is missing, 2048
bits DH parameters are automatically generated.  Note that this one-time
operation takes some time to perform and increases the startup time of the
container.

[SSVNC]: http://www.karlrunge.com/x11vnc/ssvnc.html
[DH key-exchange]: https://en.wikipedia.org/wiki/Diffie%E2%80%93Hellman_key_exchange
[OpenSSL Wiki]: https://wiki.openssl.org/index.php/Diffie_Hellman

## Building A Container

This section provides useful tips for building containers based on this
baseimage.

### Selecting Baseimage Tag

Properly select the baseimage tag to use.  For a better control and prevent
breaking your container, use a tag for an exact version of the baseimage
(e.g. `alpine-3.6-v2.0.0`).  Using the latest version of the baseimage
(`alpine-3.6`) is not recommended, since automatic upgrades between major
versions will probably break your container build/execution.

### Referencing Linux User/Group

Reference the Linux user/group under which the application is running by its ID
(`USER_ID`/`GROUP_ID`) instead of its name.  Name could change in different
baseimage versions while the ID won't.

### Default Configuration Files

Default configuration files should be stored in `/defaults` in the container.

### Adding/Removing Packages

To add or remove packages, use the helpers `add-pkg` and `del-pkg` provided by
this baseimage.  To minimze the size of the container, these tools perform
proper cleanup and make sure that no useless files are left after an addition
or removal of packages.

Also, when packages need to be added temporarily, use the `--virtual NAME`
parameter.  This allows installing missing packages and then remove them
easily using the provided `NAME` (no need to repeat given packages).  Note that
if a specified package is already installed, it will be ignored and will not be
removed automatically.

Here is an example of a command that could be added to `Dockerfile` to compile
a project:
```
RUN \
    add-pkg --virtual build-dependencies build-base cmake git && \
    # Compile your project here...
    git clone https://myproject.com/myproject.git
    ... && \
    del-pkg build-dependencies
```

Supposing that, in the example above, the `git` package is already installed
when the call to `add-pk` is performed, running `del-pkg build-dependencies`
doesn't remove it.

### Modifying Files With Sed

`sed` is a useful tool and is often used in container builds to modify files.
However, one downside of this method is that there is no easy way to determine
if `sed` actually modified the file or not.

It's for this reason that the baseimage includes a helper that gives `sed` a
"patch-like" behavior:  if the application of a sed expression results in no
change on the target file, then an error is reported.  This helper is named
`sed-patch` and has the following usage:

```
sed-patch [SED_OPT]... SED_EXPRESSION FILE
```

Note that the sed option `-i` (edit files in place) is already supplied by the
helper.

It can be used in `Dockerfile`, for example, like this:

```
RUN sed-patch 's/Replace this/By this/' /etc/myfile
```

If running this sed expression doesn't bring any change to `/etc/myfiles`, the
command fails and thus, the Docker build also.

### Modifying Baseimage Content

Try to minimize modifications to files provided by the baseimage.  This
minimizes to risk of breaking your container after using a new baseimage
version.

### Application's Data

Applications often needs to write configuration, data, logs, etc.  Always
make sure they are all written under `/config`.  This directory is a volume
intended to be mapped to a folder on the host.  The goal is to write stuff
outside the container and keep these data persistent.

A lot of applications use the environment variables defined in the
[XDG Base Directory Specification] to determine where to store
various data.  The baseimage sets these variables so they all fall under
`/config/`:

  * XDG_DATA_HOME=/config/xdg/data
  * XDG_CONFIG_HOME=/config/xdg/config
  * XDG_CACHE_HOME=/config/xdg/cache

[XDG Base Directory Specification]: https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html

### $HOME Environment Variable

The application is run under a user having its own UID.  This user can't be used
to login with, has no password, no valid login shell and no home directory.  It
is effectively a kind of user used by daemons.

Thus, by default, the `$HOME` environment variable is not set.  While this
should be fine in most case, some applications may expect the `$HOME`
environment variable to be set (since normally the application is run by a
logged user) and may not behave correctly otherwise.

To make the application happy, the home directory can be set at the beginning
of the `startapp.sh` script:
```
export HOME=/config
```

Adjust the location of the home directory to fit your needs.  However, if the
application uses the home directory to write stuff, make sure it is done in a
volume mapped to the host (e.g. `/config`),

Note that the same technique can be used by services, by exporting the home
directory into their `run` script.

### Service Dependencies

When running multiple services, service `srvB` may need to start only after
service `SrvA`.

Service dependencies are defined by creating a regular file in the service's
directory, its name being the name of the dependent service with the `.dep`
extension.  For example, touching the file:

    /etc/services.d/srvB/srvA.dep

indicates that service `srvB` depends on service `srvA`.

### Service Readiness

By default, a service is considered ready when the supervisor successfully
forked and executed the daemon.  However, some daemons do a lot of
initialization work before they're actually ready to serve.

Hopefully, the S6 supervisor supports [service startup notifications].  This is
a simple mechanism allowing daemons to notify the supervisor when they are
ready to serve.

While support for this mechanism can be implemented natively in the daemon, the
use of the [s6-notifyoncheck program] makes it possible for services to use the
S6 notification mechanism with any daemon.

[service startup notifications]: https://skarnet.org/software/s6/notifywhenup.html
[s6-notifyoncheck program]: https://skarnet.org/software/s6/s6-notifyoncheck.html

### Log Monitor

This baseimage include a simple log monitor.  This monitor allows sending
notification(s) when a particular message is detected in a log file.

This system has two main component: notification definitions and notifications
backends (targets).  Definitions describe properties of a notification (title,
message, severity, etc) and how it is triggered (i.e. filtering function).  Once
a matching string is found in a log file, a notification is triggered and sent
via one or more backends.  A backend can implement any functionality.  For
example, it could send the notification to the standard output, a file or an
online service.

#### Monitored Files

File(s) to be monitored can be set in the configuration file located at
`/etc/logmonitor/logmonitor.conf`.  There are two settings to look at:

  * `LOG_FILES`: List of absolute paths to log files to be monitored.  A log
    file is a file having new content appended to it.
  * `STATUS_FILES`: List of absolute paths to status files to be monitored.
    A status file doesn't have new content appended.  Instead, its whole content
    is refreshed/overwritten periodically.

#### Notification Definition

The definition of a notification consists in multiple files, stored in a
directory under `/etc/logmonitor/notifications.d`.  For example, definition of
notification `NOTIF` is found under `/etc/logmonitor/notifications.d/NOTIF/`.
The following table describe files part of the definition:

| File   | Mandatory? | Description |
|--------|------------|-------------|
|`filter`|Yes|Program (script or binary with executable permission) used to filter messages from a log file.  It is invoked by the log monitor with a single argument: a line from the log file.  On a match, the program should exit with a value of `0`.  Any other values is interpreted as non-match.|
|`title` |Yes|File containing the title of the notification.  To produce dynamic content, the file can be a program (script or binary with executable permission).  In this case, the program is invoked by the log monitor with the matched message from the log file as the single argument.  Output of the program is used as the notification's title.|
|`desc`  |Yes|File containing the description/message of the notification.  To produce dynamic content, the file can be a program (script or binary with executable permission).  In this case, the program is invoked by the log monitor with the matched message from the log file as the single argument.  Output of the program is used as the notification's description/message.|
|`level` |Yes|File containing severity level of the notification.  Valid severity level values are `ERROR`, `WARNING` or `INFO`.  To produce dynamic content, the file can be a program (script or binary with executable permission).  In this case, the program is invoked by the log monitor with the matched message from the log file as the single argument.  Output of the program is used as the notification's severity level.|

#### Notification Backend

Definition of notification backend is stored in a directory under
`/etc/logmonitor/targets.d`.  For example, definition of `STDOUT` backend is
found under `/etc/logmonitor/notifications.d/STDOUT/`.  The following table
describe files part of the definition:

| File       | Mandatory? | Description |
|------------|------------|-------------|
|`send`      |Yes|Program (script or binary with executable permission) that sends the notification.  It is invoked by the log monitor with the following notification properties as arguments: title, description/message and the severity level.
|`debouncing`|No|File containing the minimum amount time (in seconds) that must elapse before sending the same notification with the current backend.  A value of `0` means infinite (notification is sent once).  If this file is missing, no debouncing is done.|

By default, the baseimage contains the following notification backends:

|Backend |Description|Debouncing time|
|--------|-----------|---------------|
|`stdout`|Display a message to the standard output, make it visible in the container's log.  Message of the format is `{LEVEL}: {TITLE} {MESSAGE}`.|21 600s (6 hours)|
|`yad`|Display the notification in a window box, visible in the application's GUI.  **NOTE**: `yad` must be installed for this to work.| Infinite |

### Application Icon

A picture of your application can be added to the image.  This picture is
displayed in the WEB interface's navigation bar.  Also, multiple favicons are
generated, supporting all browsers and platforms.

Add the following command to your `Dockerfile`, with the proper URL pointing to
your master icon:  The master icon should be a square PNG image with a size of
at least 260x260 for optimal results.
```
# Generate and install favicons.
RUN \
    APP_ICON_URL=https://github.com/jlesage/docker-templates/raw/master/jlesage/images/generic-app-icon.png && \
    install_app_icon.sh "$APP_ICON_URL"
```

Favicons are generated by [RealFaviconGenerator].  You can tweak yourself their
display with the following method:
  * Generate favicons yourself with [RealFaviconGenerator].
    * Set the path to `/images/icons/`.
    * Enable versioning and set it to `v=ICON_VERSION`.
  * At the installation page, choose the `Node CLI` tab.
  * Copy the content of `faviconDescription.json`.
  * Minify the JSON using an online [JSON minifier].
    * Before running the minifier, modify the `masterPicture` field to
      `/opt/novnc/images/icons/master_icon.png`.
  * Copy-paste the result in your `Dockerfile`.  It will be passed to the
    install script.
  * Your Dockerfile should have something like:

```
# Generate and install favicons.
RUN \
    APP_ICON_URL=https://github.com/jlesage/docker-templates/raw/master/jlesage/images/generic-app-icon.png && \
    APP_ICON_DESC='{"masterPicture":"/opt/novnc/images/icons/master_icon.png","iconsPath":"/images/icons/","design":{"ios":{"pictureAspect":"backgroundAndMargin","backgroundColor":"#ffffff","margin":"14%","assets":{"ios6AndPriorIcons":false,"ios7AndLaterIcons":false,"precomposedIcons":false,"declareOnlyDefaultIcon":true}},"desktopBrowser":{},"windows":{"pictureAspect":"noChange","backgroundColor":"#2d89ef","onConflict":"override","assets":{"windows80Ie10Tile":false,"windows10Ie11EdgeTiles":{"small":false,"medium":true,"big":false,"rectangle":false}}},"androidChrome":{"pictureAspect":"noChange","themeColor":"#ffffff","manifest":{"display":"standalone","orientation":"notSet","onConflict":"override","declared":true},"assets":{"legacyIcon":false,"lowResolutionIcons":false}},"safariPinnedTab":{"pictureAspect":"silhouette","themeColor":"#5bbad5"}},"settings":{"scalingAlgorithm":"Mitchell","errorOnImageTooSmall":false},"versioning":{"paramName":"v","paramValue":"ICON_VERSION"}}' && \
    install_app_icon.sh "$APP_ICON_URL" "$APP_ICON_DESC"
```

[RealFaviconGenerator]: https://realfavicongenerator.net/
[JSON minifier]: http://www.cleancss.com/json-minify/

### Maximizing Only the Main Window

By default, the application's window is maximized and decorations are hidden.
However, when the application has multiple windows, this behavior may need to
be restricted only to the main one.

This can be achieved by matching on more window parameters: class, name, role,
title and type.  By default, only the `type` parameter is used and must equal to
`normal`.

To find all parameters of the main window:
  - While the application is running and the main window is focused, login to
    the container.
```
docker exec -ti [container name or id] sh
```
  - Execute `obxprop --root | grep "^_NET_ACTIVE_WINDOW"`.  The output will look
    like:
```
_NET_ACTIVE_WINDOW(WINDOW) = 16777220
```
  - Using this ID, show the parameters by executing
    `obxprop --id [MAIN WINDOW ID] | grep "^_OB_APP"`. The output will look
    like:
```
_OB_APP_TYPE(UTF8_STRING) = "normal"
_OB_APP_CLASS(UTF8_STRING) = "Google-chrome"
_OB_APP_NAME(UTF8_STRING) = "google-chrome"
_OB_APP_ROLE(UTF8_STRING) =
_OB_APP_TITLE(UTF8_STRING) = "Google Chrome"
```

Finally, in the `Dockerfile` of your container, modify the configuration file of
`openbox` (located at `/etc/xdg/openbox/rc.xml`) to apply window restriction.
Usually, specifying the window's title is enough.

```
sed-patch 's/<application type="normal">/<application type="normal" title="Google Chrome">/' /etc/xdg/openbox/rc.xml
```

See the openbox's documentation for more details: http://openbox.org/wiki/Help:Applications
### S6 Overlay Documentation
* Make sure to read the [S6 overlay documentation].  It contains information
that can help building your image.  For example, the S6 overlay allows you to
easily add initialization scripts and services.

[S6 overlay documentation]: https://github.com/just-containers/s6-overlay/blob/master/README.md

[TimeZone]: http://en.wikipedia.org/wiki/List_of_tz_database_time_zones
