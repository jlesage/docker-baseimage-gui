# A minimal docker baseimage to ease creation of X graphical application containers
[![Release](https://img.shields.io/github/release/jlesage/docker-baseimage-gui.svg?logo=github&style=for-the-badge)](https://github.com/jlesage/docker-baseimage-gui/releases/latest)
[![Build Status](https://img.shields.io/github/actions/workflow/status/jlesage/docker-baseimage-gui/build-baseimage.yml?logo=github&branch=master&style=for-the-badge)](https://github.com/jlesage/docker-baseimage-gui/actions/workflows/build-baseimage.yml)
[![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg?style=for-the-badge)](https://paypal.me/JocelynLeSage)

This is a docker baseimage that can be used to create containers able to run
any X application on a headless server very easily.  The application's GUI
is accessed through a modern web browser (no installation or configuration
needed on the client side) or via any VNC client.

## Images

Different docker images are available:

| Base Distribution  | Docker Image Base Tag | Size |
|--------------------|-----------------------|------|
| [Alpine 3.14]      | alpine-3.14           | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/alpine-3.14-v4?style=for-the-badge)](#)  |
| [Alpine 3.15]      | alpine-3.15           | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/alpine-3.15-v4?style=for-the-badge)](#)  |
| [Alpine 3.16]      | alpine-3.16           | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/alpine-3.16-v4?style=for-the-badge)](#)  |
| [Alpine 3.17]      | alpine-3.17           | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/alpine-3.17-v4?style=for-the-badge)](#)  |
| [Alpine 3.18]      | alpine-3.18           | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/alpine-3.18-v4?style=for-the-badge)](#)  |
| [Debian 10]        | debian-10             | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/debian-10-v4?style=for-the-badge)](#)    |
| [Debian 11]        | debian-11             | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/debian-11-v4?style=for-the-badge)](#)    |
| [Ubuntu 16.04 LTS] | ubuntu-16.04          | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/ubuntu-16.04-v4?style=for-the-badge)](#) |
| [Ubuntu 18.04 LTS] | ubuntu-18.04          | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/ubuntu-18.04-v4?style=for-the-badge)](#) |
| [Ubuntu 20.04 LTS] | ubuntu-20.04          | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/ubuntu-20.04-v4?style=for-the-badge)](#) |
| [Ubuntu 22.04 LTS] | ubuntu-22.04          | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/ubuntu-22.04-v4?style=for-the-badge)](#) |

[Alpine 3.14]: https://alpinelinux.org
[Alpine 3.15]: https://alpinelinux.org
[Alpine 3.16]: https://alpinelinux.org
[Alpine 3.17]: https://alpinelinux.org
[Alpine 3.18]: https://alpinelinux.org
[Debian 10]: https://www.debian.org/releases/buster/
[Debian 11]: https://www.debian.org/releases/bullseye/
[Ubuntu 16.04 LTS]: http://releases.ubuntu.com/16.04/
[Ubuntu 18.04 LTS]: http://releases.ubuntu.com/18.04/
[Ubuntu 20.04 LTS]: http://releases.ubuntu.com/20.04/
[Ubuntu 22.04 LTS]: http://releases.ubuntu.com/22.04/

### Content

Here are the main components of the baseimage:

  * An init system.
  * A process supervisor, with proper PID 1 functionality (proper reaping of
    processes).
  * [TigerVNC], a X server with an integrated VNC server.
  * [Openbox], a window manager.
  * [noVNC], a HTML5 VNC client.
  * [NGINX], a high-performance HTTP server.
  * Useful tools to ease container building.
  * Environment to better support dockerized applications.

[TigerVNC]: https://tigervnc.org
[Openbox]: http://openbox.org
[noVNC]: https://github.com/novnc/noVNC
[NGINX]: https://www.nginx.com

### Versioning

Images are versioned.  Version number follows the [semantic versioning].  The
version format is `MAJOR.MINOR.PATCH`, where an increment of the:

  - `MAJOR` version indicates that a backwards-incompatible change has been done.
  - `MINOR` version indicates that functionality has been added in a backwards-compatible manner.
  - `PATCH` version indicates that a bug fix has been done in a backwards-compatible manner.

[semantic versioning]: https://semver.org

### Tags

For each distribution-specific image, multiple tags are available:

| Tag           | Description                                              |
|---------------|----------------------------------------------------------|
| distro-vX.Y.Z | Exact version of the image.                              |
| distro-vX.Y   | Latest version of a specific minor version of the image. |
| distro-vX     | Latest version of a specific major version of the image. |

## Getting started

The `Dockerfile` for your application can be very simple, as only three things
are required:

  * Instructions to install the application.
  * A script that starts the application (stored at `/startapp.sh` in
    container).
  * The name of the application.

Here is an example of a docker file that would be used to run the `xterm`
terminal.

In `Dockerfile`:
```Dockerfile
# Pull base image.
FROM jlesage/baseimage-gui:alpine-3.15-v4

# Install xterm.
RUN add-pkg xterm

# Copy the start script.
COPY startapp.sh /startapp.sh

# Set the name of the application.
RUN set-cont-env APP_NAME "Xterm"

```

In `startapp.sh`:
```shell
#!/bin/sh
exec /usr/bin/xterm
```

Then, build your docker image:

    docker build -t docker-xterm .

And run it:

    docker run --rm -p 5800:5800 -p 5900:5900 docker-xterm

You should be able to access the xterm GUI by opening in a web browser:

```
http://[HOST IP ADDR]:5800
```

## Documentation

Full documentation is available at https://github.com/jlesage/docker-baseimage-gui.

