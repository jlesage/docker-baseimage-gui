# A minimal docker baseimage to ease creation of X graphical application containers
[![Build Status](https://travis-ci.org/jlesage/docker-baseimage-gui.svg?branch=master)](https://travis-ci.org/jlesage/docker-baseimage-gui)

This is a docker baseimage that can be used to create containers able to run any
X application on a headless server very easily.  The application's GUI is
accessed through a modern web browser (no installation or configuration needed
on client side) or via any VNC client.

## Images
Different docker images are available:

| Base distribution  | Tag            | Size |
|--------------------|----------------|------|
| [Alpine 3.5]       | alpine-3.5     | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:alpine-3.5.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:alpine-3.5 "Get your own image badge on microbadger.com") |
| [Alpine 3.5]       | alpine-3.5-glibc     | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:alpine-3.5-glibc.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:alpine-3.5-glibc "Get your own image badge on microbadger.com") |
| [Debian 8]         | debian-8       | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:debian-8.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:debian-8/ "Get your own image badge on microbadger.com") |
| [Ubuntu 16.04 LTS] | ubuntu-16.04   | [![](https://images.microbadger.com/badges/image/jlesage/baseimage-gui:ubuntu-16.04.svg)](http://microbadger.com/#/images/jlesage/baseimage-gui:ubuntu-16.04 "Get your own image badge on microbadger.com") |

[Alpine 3.5]: https://alpinelinux.org
[Debian 8]: https://www.debian.org/releases/jessie/
[Ubuntu 16.04 LTS]: http://releases.ubuntu.com/16.04/

Due to its size, the `Alpine` image is recommended.  However, it may be harder
to integrate your application (especially third party ones without source code),
because:
 1. Packages repository may not be as complete as `Ubuntu`/`Debian`.
 2. Third party applications may not support `Alpine`.
 3. The `Alpine` distribution uses the [musl] C standard library instead of
 GNU C library ([glibc]).
  * NOTE: Using the `Alpine` image with glibc integrated (`alpine-3.5-glibc`
    tag) may ease integration of applications.

The next choice is to use the `Debian` image.  It provides a great compatibility
and its size is smaller than the `Ubuntu` one.  Finally, if for anuy reason you
prefer an `Ubuntu` image, one based on the stable `16.04 LTS` version. is
provided.

[musl]: https://www.musl-libc.org/
[glibc]: https://www.gnu.org/software/libc/

### Content
Here are the main components of the baseimage:
  * [S6-overlay], a process supervisor for containers.
  * [x11vnc], a X11 VNC server.
  * [xvfb], a X virtual framebuffer display server.
  * [openbox], a windows manager.
  * [noVNC], a HTML5 VNC client.

[S6-overlay]: https://github.com/just-containers/s6-overlay
[x11vnc]: http://www.karlrunge.com/x11vnc/
[xvfb]: http://www.x.org/releases/X11R7.6/doc/man/man1/Xvfb.1.xhtml
[openbox]: http://openbox.org
[noVNC]: https://github.com/novnc/noVNC

## Getting started
The `Dockerfile` for your X application can be very simple, as only three things
are required:

  * Instructions to install the X application.
  * A script that starts the X application (stored at `/startapp.sh` in
    container).
  * The name of the X application.

Here is an example of a docker file that would be used to run the `xterm`
terminal.

In ``Dockerfile``:
```
# Pull base image.
FROM jlesage/docker-baseimage-gui:debian

# Install xterm.
RUN apt-get update apt-get install -y --no-install-recommends \
        xterm && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/tmp/* /tmp/*

# Copy the start script.
COPY startapp.sh /startapp.sh

# Set the name of the application.
ENV APP_NAME="Xterm"
```

In `startapp.sh`:
```
#!/bin/bash
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
and its X application.  The following list give more details about them.

Environment variables can be set directly in your `Dockerfile` via the `ENV`
instruction or dynamically by adding one or more arguments `-e "<VAR>=<VALUE>"`
to the `docker run` command.

- **APP_NAME**
  Name of the application.  This allows VNC clients to show a title that
  identifies your application.  Default value is `DockerApp`.
- **DISPLAY_WIDTH**
  Width (in pixels) of the display/application's window.  Default is `1280`.
- **DISPLAY_HEIGHT**
  Height (in pixels) of the display/application's window.  Default is `720`.
- **KEEP_GUIAPP_RUNNING**
  When set to `0`, the container terminates when the application exits. When set
  to `1`, the X application is automatically restarted when it terminates.
  Default is `0`.
- **VNC_PASSWORD**
  Password needed to connect to the application's GUI.  By default, no password
  is needed.  The VNC password can also be set via a file.  See the
  [VNC Pasword](#vnc-password) section for more details.

  **WARNING**: This is a very basic way to restrict access to the application
  and it should not be considered as secure in any way.
- **TZ**
  Timezone of the container.  For example: `America/Montreal`.  The complete
  list can be found on [Wikipedia].
- **USER_ID**
  ID of the user the X application run as.  Default is `1000`.  See
  [User/Group IDs](#usergroup-ids) to better understand when this should be set.
- **GROUP_ID**
  ID of the group the X application run as.  Default is `1000`.  See
  [User/Group IDs](#usergroup-ids) to better understand when this should be set.

## Config Directory
Inside the container, the application's configuration should be stored in the
`/config` directory.

This directory is also used to store the VNC password.  See the
[VNC Pasword](#vnc-password) section for more details.

**NOTE**: During the container startup, the user which runs the application
(i.e. user defined by `USER_ID`) will claim ownership of the entire content of
this directory.

[Wikipedia]: http://en.wikipedia.org/wiki/List_of_tz_database_time_zones

## Ports

Here is the list of ports used by container.  They can be mapped to the host
via the `-p <HOST_PORT>:<CONTAINER_PORT>` parameter.  The port number inside the
container cannot be changed, but you are free to use any port on the host side.

| Port | Mapping to host | Description |
|------|-----------------|-------------|
| 5800 | Mandatory  | Port used to access to the application's GUI via the web interface. |
| 5900 | Mandatory  | Port used to access to the application's GUI via the VNC protocol.  |

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

## Accessing the GUI

Assuming the host is mapped to the same ports as the container, the graphical
interface of the application can be accessed via:

  * A web browser:
```
http://<HOST IP ADDR>:5800
```

  * Any VNC client:
```
<HOST IP ADDR>:5900
```

If different ports are mapped to the host, make sure they respect the
following formula:

    VNC_PORT = HTTP_PORT + 100

This is to make sure accessing the GUI with a web browser can be done without
specifying the VNC port manually.  If this is not possible, then specify
explicitly the VNC port like this:

    http://<HOST IP ADDR>:5800/?port=<VNC PORT>

## VNC Password
To restrict access to your application, a password can be specified.  This can
be done via two methods:
  * By using the `VNC_PASSWORD` environment variable.
  * By creating a `.vncpass_clear` file at the root of the `/config` volume.
  This file should contains the password (in clear).  During the container
  startup, content of the file is obfuscated and moved to `.vncpass`.

**NOTE**: This is a very basic way to restrict access to the application and it
should not be considered as secure in any way.

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

## Security
TBD

## Notes
* Make sure to read the [S6 overlay documentation].  It contains information
that can help building your image.  For example, the S6 overlay allows you to
easily add initialization scripts and services.

[S6 overlay documentation]: https://github.com/just-containers/s6-overlay/blob/master/README.md
