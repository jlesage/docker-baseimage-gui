# A minimal docker baseimage to ease creation of X graphical application containers
[![Release](https://img.shields.io/github/release/jlesage/docker-baseimage-gui.svg?logo=github&style=for-the-badge)](https://github.com/jlesage/docker-baseimage-gui/releases/latest)
[![Build Status](https://img.shields.io/github/actions/workflow/status/jlesage/docker-baseimage-gui/build-baseimage.yml?logo=github&branch=master&style=for-the-badge)](https://github.com/jlesage/docker-baseimage-gui/actions/workflows/build-baseimage.yml)
[![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg?style=for-the-badge)](https://paypal.me/JocelynLeSage)

This Docker baseimage simplifies creating containers to run any X graphical
application on a headless server. The application's GUI is accessed via a modern
web browser (no installation or configuration needed on the client side) or via
any VNC client.

## Table of Contents

   * [Images](#images)
      * [Versioning](#versioning)
      * [Content](#content)
   * [Getting Started](#getting-started)
   * [Using the Baseimage](#using-the-baseimage)
      * [Selecting a Baseimage](#selecting-a-baseimage)
      * [Container Startup Sequence](#container-startup-sequence)
      * [Container Shutdown Sequence](#container-shutdown-sequence)
      * [Environment Variables](#environment-variables)
         * [Public Environment Variables](#public-environment-variables)
         * [Internal Environment Variables](#internal-environment-variables)
         * [Adding/Removing Internal Environment Variables](#addingremoving-internal-environment-variables)
         * [Availability](#availability)
         * [Docker Secrets](#docker-secrets)
      * [Ports](#ports)
      * [User/Group IDs](#usergroup-ids)
      * [Initialization Scripts](#initialization-scripts)
      * [Finalization Scripts](#finalization-scripts)
      * [Services](#services)
         * [Service Group](#service-group)
         * [Default Service](#default-service)
         * [Service Readiness](#service-readiness)
      * [Helpers](#helpers)
         * [Adding/Removing Packages](#addingremoving-packages)
         * [Modifying Files with Sed](#modifying-files-with-sed)
         * [Evaluating Boolean Values](#evaluating-boolean-values)
         * [Taking Ownership of a Directory](#taking-ownership-of-a-directory)
         * [Setting Internal Environment Variables](#setting-internal-environment-variables)
      * [Configuration Directory](#configuration-directory)
         * [Application's Data Directories](#applications-data-directories)
      * [Locales](#locales)
      * [Container Log](#container-log)
      * [Logrotate](#logrotate)
      * [Log Monitor](#log-monitor)
         * [Notification Definition](#notification-definition)
         * [Notification Backend](#notification-backend)
      * [Accessing the GUI](#accessing-the-gui)
      * [Security](#security)
         * [SSVNC](#ssvnc)
         * [Certificates](#certificates)
         * [VNC Password](#vnc-password)
         * [DH Parameters](#dh-parameters)
         * [Web Authentication](#web-authentication)
            * [Configuring User Credentials](#configuring-user-credentials)
      * [Reverse Proxy](#reverse-proxy)
         * [Routing Based on Hostname](#routing-based-on-hostname)
         * [Routing Based on URL Path](#routing-based-on-url-path)
      * [Web Audio](#web-audio)
      * [Web File Manager](#web-file-manager)
      * [Application Icon](#application-icon)
      * [Dark Mode](#dark-mode)
         * [GTK](#gtk)
         * [Qt](#qt)
      * [Tips and Best Practices](#tips-and-best-practices)
         * [Do Not Modify Baseimage Content](#do-not-modify-baseimage-content)
         * [Default Configuration Files](#default-configuration-files)
         * [The $HOME Variable](#the-home-variable)
         * [Referencing Linux User/Group](#referencing-linux-usergroup)
         * [Using rootfs Directory](#using-rootfs-directory)
         * [Maximizing Only the Main Window](#maximizing-only-the-main-window)
         * [Adaptations from Version 3.x](#adaptations-from-version-3x)

## Images

This baseimage is available for multiple Linux distributions:

| Linux Distribution | Docker Image Tag      | Size |
|--------------------|-----------------------|------|
| [Alpine 3.16]      | alpine-3.16-vX.Y.Z    | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/alpine-3.16-v4?style=for-the-badge)](#)  |
| [Alpine 3.17]      | alpine-3.17-vX.Y.Z    | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/alpine-3.17-v4?style=for-the-badge)](#)  |
| [Alpine 3.18]      | alpine-3.18-vX.Y.Z    | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/alpine-3.18-v4?style=for-the-badge)](#)  |
| [Alpine 3.19]      | alpine-3.19-vX.Y.Z    | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/alpine-3.19-v4?style=for-the-badge)](#)  |
| [Alpine 3.20]      | alpine-3.20-vX.Y.Z    | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/alpine-3.20-v4?style=for-the-badge)](#)  |
| [Alpine 3.21]      | alpine-3.21-vX.Y.Z    | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/alpine-3.21-v4?style=for-the-badge)](#)  |
| [Alpine 3.22]      | alpine-3.22-vX.Y.Z    | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/alpine-3.22-v4?style=for-the-badge)](#)  |
| [Debian 10]        | debian-10-vX.Y.Z      | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/debian-10-v4?style=for-the-badge)](#)    |
| [Debian 11]        | debian-11-vX.Y.Z      | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/debian-11-v4?style=for-the-badge)](#)    |
| [Debian 12]        | debian-12-vX.Y.Z      | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/debian-12-v4?style=for-the-badge)](#)    |
| [Ubuntu 16.04 LTS] | ubuntu-16.04-vX.Y.Z   | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/ubuntu-16.04-v4?style=for-the-badge)](#) |
| [Ubuntu 18.04 LTS] | ubuntu-18.04-vX.Y.Z   | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/ubuntu-18.04-v4?style=for-the-badge)](#) |
| [Ubuntu 20.04 LTS] | ubuntu-20.04-vX.Y.Z   | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/ubuntu-20.04-v4?style=for-the-badge)](#) |
| [Ubuntu 22.04 LTS] | ubuntu-22.04-vX.Y.Z   | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/ubuntu-22.04-v4?style=for-the-badge)](#) |
| [Ubuntu 24.04 LTS] | ubuntu-24.04-vX.Y.Z   | [![](https://img.shields.io/docker/image-size/jlesage/baseimage-gui/ubuntu-24.04-v4?style=for-the-badge)](#) |

Docker image tags follow this structure:

| Tag           | Description                                              |
|---------------|----------------------------------------------------------|
| distro-vX.Y.Z | Exact version of the image.                              |
| distro-vX.Y   | Latest version of a specific minor version of the image. |
| distro-vX     | Latest version of a specific major version of the image. |

View all available tags on [Docker Hub] or check the [Releases] page for version
details.

[Alpine 3.16]: https://alpinelinux.org/posts/Alpine-3.16.0-released.html
[Alpine 3.17]: https://alpinelinux.org/posts/Alpine-3.17.0-released.html
[Alpine 3.18]: https://alpinelinux.org/posts/Alpine-3.18.0-released.html
[Alpine 3.19]: https://alpinelinux.org/posts/Alpine-3.19.0-released.html
[Alpine 3.20]: https://alpinelinux.org/posts/Alpine-3.20.0-released.html
[Alpine 3.21]: https://alpinelinux.org/posts/Alpine-3.21.0-released.html
[Alpine 3.22]: https://alpinelinux.org/posts/Alpine-3.22.0-released.html
[Debian 10]: https://www.debian.org/releases/buster/
[Debian 11]: https://www.debian.org/releases/bullseye/
[Debian 12]: https://www.debian.org/releases/bookworm/
[Ubuntu 16.04 LTS]: http://releases.ubuntu.com/16.04/
[Ubuntu 18.04 LTS]: http://releases.ubuntu.com/18.04/
[Ubuntu 20.04 LTS]: http://releases.ubuntu.com/20.04/
[Ubuntu 22.04 LTS]: http://releases.ubuntu.com/22.04/
[Ubuntu 24.04 LTS]: http://releases.ubuntu.com/24.04/

[Releases]: https://github.com/jlesage/docker-baseimage-gui/releases
[Docker Hub]: https://hub.docker.com/r/jlesage/baseimage-gui/tags

### Versioning

Images adhere to [semantic versioning]. The version format is
`MAJOR.MINOR.PATCH`, where an increment in the:

  - `MAJOR` version indicates a backward-incompatible change.
  - `MINOR` version indicates functionality added in a backward-compatible manner.
  - `PATCH` version indicates a bug fix in a backward-compatible manner.

[semantic versioning]: https://semver.org

### Content

The baseimage includes the following key components:

  - An initialization system for container startup.
  - A process supervisor with proper PID 1 functionality (e.g., process
    reaping).
  - [TigerVNC], an X server with an integrated VNC server.
  - [Openbox], a lightweight window manager.
  - [noVNC], an HTML5 VNC client.
  - [NGINX], a high-performance HTTP server.
  - Tools to simplify container creation.
  - An environment optimized for Dockerized applications.

[TigerVNC]: https://tigervnc.org
[Openbox]: http://openbox.org
[noVNC]: https://github.com/novnc/noVNC
[NGINX]: https://www.nginx.com

## Getting Started

Creating a Docker container for an application using this baseimage is
straightforward. You need at least three components in your `Dockerfile`:

  - Instructions to install the application and its dependencies.
  - A script to start the application, stored at `/startapp.sh` in the
    container.
  - The name of the application.

Below is an example of a `Dockerfile` and `startapp.sh` for running the `xterm`
terminal:

**Dockerfile**:

```dockerfile
# Pull the baseimage.
FROM jlesage/baseimage-gui:alpine-3.19-v4

# Install xterm.
RUN add-pkg xterm

# Copy the start script.
COPY startapp.sh /startapp.sh

# Set the application name.
RUN set-cont-env APP_NAME "Xterm"
```

**startapp.sh**:

```shell
#!/bin/sh
exec /usr/bin/xterm
```

Make the script executable:

```shell
chmod +x startapp.sh
```

Build the Docker image:

```shell
docker build -t docker-xterm .
```

Run the container, mapping ports for web and VNC access:

```shell
docker run --rm -p 5800:5800 -p 5900:5900 docker-xterm
```

Access the GUI via a web browser at:

```text
http://<HOST_IP_ADDR>:5800
```

## Using the Baseimage

### Selecting a Baseimage

Using a baseimage based on Alpine Linux is recommended, not only for its compact
size, but also because Alpine Linux, built with [musl] and [BusyBox], is
designed for security, simplicity, and resource efficiency.

However, integrating applications not available in Alpine's software repository
or those lacking source code can be challenging. Alpine Linux uses the [musl] C
standard library instead of the GNU C library ([glibc]), which most applications
are built against. Compatibility between these libraries is limited.

Alternatively, Debian and Ubuntu images are well-known Linux distributions
offering excellent compatibility with existing applications.

[musl]: https://www.musl-libc.org
[BusyBox]: https://busybox.net
[glibc]: https://www.gnu.org/software/libc/

### Container Startup Sequence

When the container starts, it executes the following steps:

  - The init process (`/init`) is invoked.
  - Internal environment variables are loaded from `/etc/cont-env.d`.
  - Initialization scripts under `/etc/cont-init.d` are executed in alphabetical
    order.
  - Control is given to the process supervisor.
  - The service group `/etc/services.d/default` is loaded, along with its
    dependencies.
  - Services are started in the correct order.
  - The container is now fully started.

### Container Shutdown Sequence

The container can shut down in two scenarios:

  1. When the implemented application terminates.
  2. When Docker initiates a shutdown (e.g., via the `docker stop` command).

In both cases, the shutdown sequence is as follows:

  - All services are terminated in reverse order.
  - If processes are still running, a `SIGTERM` signal is sent to all.
  - After 5 seconds, remaining processes are forcefully terminated via the
    `SIGKILL` signal.
  - The process supervisor executes the exit script (`/etc/services.d/exit`).
  - The exit script runs finalization scripts in `/etc/cont-finish.d/` in
    alphabetical order.
  - The container is fully stopped.

### Environment Variables

Environment variables enable customization of the container and application
behavior. They are categorized into two types:

  - **Public**: These variables are intended for users of the container. They
    provide a way to configure it and are declared in the `Dockerfile` using the
    `ENV` instruction. Their values can be set during container creation with
    the `-e "<VAR>=<VALUE>"` argument of the `docker run` command. Many Docker
    container management systems use these variables to provide configuration
    options to users.

  - **Internal**: These variables are not meant to be modified by users. They
    are useful for the application but not intended for external configuration.

> [!NOTE]
> If a variable is defined as both internal and public, the public value takes
> precedence.

#### Public Environment Variables

The baseimage provides the following public environment variables:

| Variable       | Description                                  | Default |
|----------------|----------------------------------------------|---------|
|`USER_ID`| ID of the user the application runs as. See [User/Group IDs](#usergroup-ids) for details. | `1000` |
|`GROUP_ID`| ID of the group the application runs as. See [User/Group IDs](#usergroup-ids) for details. | `1000` |
|`SUP_GROUP_IDS`| Comma-separated list of supplementary group IDs for the application. | (no value) |
|`UMASK`| Mask controlling permissions for newly created files and folders, specified in octal notation. By default, `0022` ensures files and folders are readable by all but writable only by the owner. See the umask calculator at http://wintelguy.com/umask-calc.pl. | `0022` |
|`LANG`| Sets the [locale](https://en.wikipedia.org/wiki/Locale_(computer_software)), defining the application's language, if supported. Format is `language[_territory][.codeset]`, where language is an [ISO 639 language code](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes), territory is an [ISO 3166 country code](https://en.wikipedia.org/wiki/ISO_3166-1#Current_codes), and codeset is a character set, like `UTF-8`. For example, Australian English using UTF-8 is `en_AU.UTF-8`. | `en_US.UTF-8` |
|`TZ`| [TimeZone](http://en.wikipedia.org/wiki/List_of_tz_database_time_zones) used by the container. The timezone can also be set by mapping `/etc/localtime` between the host and the container. | `Etc/UTC` |
|`KEEP_APP_RUNNING`| When set to `1`, the application is automatically restarted if it crashes or terminates. | `0` |
|`APP_NICENESS`| Priority at which the application runs. A niceness value of -20 is the highest, 19 is the lowest and 0 the default. **NOTE**: A negative niceness (priority increase) requires additional permissions. The container must be run with the Docker option `--cap-add=SYS_NICE`. | `0` |
|`INSTALL_PACKAGES`| Space-separated list of packages to install during container startup. Packages are installed from the repository of the Linux distribution the container is based on. | (no value) |
|`PACKAGES_MIRROR`| Mirror of the repository to use when installing packages. | (no value) |
|`CONTAINER_DEBUG`| When set to `1`, enables debug logging. | `0` |
|`DISPLAY_WIDTH`| Width (in pixels) of the application's window. | `1920` |
|`DISPLAY_HEIGHT`| Height (in pixels) of the application's window. | `1080` |
|`DARK_MODE`| When set to `1`, enables dark mode for the application. See Dark Mode](#dark-mode) for details. | `0` |
|`WEB_AUDIO`| When set to `1`, enables audio support, allowing audio produced by the application to play through the browser. See [Web Audio](#web-audio) for details. | `0` |
|`WEB_FILE_MANAGER`| When set to `1`, enables the web file manager, allowing interaction with files inside the container through the web browser, supporting operations like renaming, deleting, uploading, and downloading. See [Web File Manager](#web-file-manager) for details. | `0` |
|`WEB_FILE_MANAGER_ALLOWED_PATHS`| Comma-separated list of paths within the container that the file manager can access. By default, the container's entire filesystem is not accessible, and this variable specifies allowed paths. If set to `AUTO`, commonly used folders and those mapped to the container are automatically allowed. The value `ALL` allows access to all paths (no restrictions). See [Web File Manager](#web-file-manager) for details. | `AUTO` |
|`WEB_FILE_MANAGER_DENIED_PATHS`| Comma-separated list of paths within the container that the file manager cannot access. A denied path takes precedence over an allowed path. See [Web File Manager](#web-file-manager) for details. | (no value) |
|`WEB_AUTHENTICATION`| When set to `1`, protects the application's GUI with a login page when accessed via a web browser. Access is granted only with valid credentials. This feature requires the secure connection to be enabled. See [Web Authentication](#web-authentication) for details. | `0` |
|`WEB_AUTHENTICATION_TOKEN_VALIDITY_TIME`| Lifetime of a token, in hours. A token is assigned to the user after successful login. As long as the token is valid, the user can access the application's GUI without logging in again. Once the token expires, the login page is displayed again. | `24` |
|`WEB_AUTHENTICATION_USERNAME`| Optional username for web authentication. Provides a quick and easy way to configure credentials for a single user. For more secure configuration or multiple users, see the [Web Authentication](#web-authentication) section. | (no value) |
|`WEB_AUTHENTICATION_PASSWORD`| Optional password for web authentication. Provides a quick and easy way to configure credentials for a single user. For more secure configuration or multiple users, see the [Web Authentication](#web-authentication) section. | (no value) |
|`SECURE_CONNECTION`| When set to `1`, uses an encrypted connection to access the application's GUI (via web browser or VNC client). See [Security](#security) for details. | `0` |
|`SECURE_CONNECTION_VNC_METHOD`| Method used for encrypted VNC connections. Possible values are `SSL` or `TLS`. See [Security](#security) for details. | `SSL` |
|`SECURE_CONNECTION_CERTS_CHECK_INTERVAL`| Interval, in seconds, at which the system checks if web or VNC certificates have changed. When a change is detected, affected services are automatically restarted. A value of `0` disables the check. | `60` |
|`WEB_LISTENING_PORT`| Port used by the web server to serve the application's GUI. This port is internal to the container and typically does not need to be changed. By default, a container uses the default bridge network, requiring each internal port to be mapped to an external port (using the `-p` or `--publish` argument). If another network type is used, changing this port may prevent conflicts with other services/containers. **NOTE**: A value of `-1` disables HTTP/HTTPS access to the application's GUI. | `5800` |
|`VNC_LISTENING_PORT`| Port used by the VNC server to serve the application's GUI. This port is internal to the container and typically does not need to be changed. By default, a container uses the default bridge network, requiring each internal port to be mapped to an external port (using the `-p` or `--publish` argument). If another network type is used, changing this port may prevent conflicts with other services/containers. **NOTE**: A value of `-1` disables VNC access to the application's GUI. | `5900` |
|`VNC_PASSWORD`| Password required to connect to the application's GUI. See the [VNC Password](#vnc-password) section for details. | (no value) |
|`ENABLE_CJK_FONT`| When set to `1`, installs the open-source font `WenQuanYi Zen Hei`, supporting a wide range of Chinese/Japanese/Korean characters. | `0` |

#### Internal Environment Variables

The baseimage provides the following internal environment variables:

| Variable       | Description                                  | Default |
|----------------|----------------------------------------------|---------|
|`APP_NAME`| Name of the implemented application. | `DockerApp` |
|`APP_VERSION`| Version of the implemented application. | (no value) |
|`DOCKER_IMAGE_VERSION`| Version of the Docker image that implements the application. | (no value) |
|`DOCKER_IMAGE_PLATFORM`| Platform (OS/CPU architecture) of the Docker image that implements the application. | (no value) |
|`HOME`| Home directory. | (no value) |
|`XDG_CONFIG_HOME`| Defines the base directory for user-specific configuration files. | `/config/xdg/config` |
|`XDG_DATA_HOME`| Defines the base directory for user-specific data files. | `/config/xdg/data` |
|`XDG_CACHE_HOME`| Defines the base directory for user-specific non-essential data files. | `/config/xdg/cache` |
|`TAKE_CONFIG_OWNERSHIP`| When set to `0`, ownership of the `/config` directory's contents is not taken during container startup. | `1` |
|`INSTALL_PACKAGES_INTERNAL`| Space-separated list of packages to install during container startup. Packages are installed from the repository of the Linux distribution the container is based on. | (no value) |
|`SUP_GROUP_IDS_INTERNAL`| Comma-separated list of supplementary group IDs for the application, merged with those supplied by `SUP_GROUP_IDS`. | (no value) |
|`SERVICES_GRACETIME`| During container shutdown, defines the time (in milliseconds) allowed for services to gracefully terminate before sending the SIGKILL signal to all. | `5000` |

#### Adding/Removing Internal Environment Variables

Internal environment variables are defined by creating a file in
`/etc/cont-env.d/` inside the container, where the file's name is the variable
name and its content is the value.

If the file is executable, the init process executes it, and the environment
variable's value is taken from its standard output.

> [!NOTE]
> If the program exits with return code `100`, the environment variable is not
> set (distinct from being set with an empty value).

> [!NOTE]
> Any stderr output from the program is redirected to the container's log.

> [!NOTE]
> The `set-cont-env` helper can be used to set internal environment variables
> from the Dockerfile.

#### Availability

Public environment variables are defined during container creation and are
available to scripts and services as soon as the container starts.

Internal environment variables are loaded during container startup, before
initialization scripts and services run, ensuring their availability.

#### Docker Secrets

[Docker secrets](https://docs.docker.com/engine/swarm/secrets/) is a
functionality available to swarm services that offers a secure way to store
sensitive information such as usernames, passwords, etc.

This baseimage automatically exports Docker secrets as environment variables if
they follow the naming convention `CONT_ENV_<environment variable name>`.

For example, a secret named `CONT_ENV_MY_PASSWORD` creates the environment
variable `MY_PASSWORD` with the secret's content.

### Ports

The baseimage uses the following ports. With a container using the default
bridge network, these ports can be mapped to the host via the
`-p <HOST_PORT>:<CONTAINER_PORT>` parameter.

| Port | Mapping to Host | Description |
|------|-----------------|-------------|
| 5800 | Optional        | Port to access the application's GUI via the web interface. Mapping to the host is optional if web access is not needed. For non-default bridge networks, the port can be changed with the `WEB_LISTENING_PORT` environment variable. |
| 5900 | Optional        | Port to access the application's GUI via the VNC protocol. Mapping to the host is optional if VNC access is not needed. For non-default bridge networks, the port can be changed with the `VNC_LISTENING_PORT` environment variable. |

### User/Group IDs

When mapping data volumes (using the `-v` flag of the `docker run` command),
permission issues may arise between the host and the container. Files and
folders in a data volume are owned by a user, which may differ from the user
running the application. Depending on permissions, this could prevent the
container from accessing the shared volume.

To avoid this, specify the user the application should run as using the
`USER_ID` and `GROUP_ID` environment variables.

To find the appropriate IDs, run the following command on the host for the user
owning the data volume:

```shell
id <username>
```

This produces output like:

```text
uid=1000(myuser) gid=1000(myuser) groups=1000(myuser),4(adm),24(cdrom),27(sudo),46(plugdev),113(lpadmin)
```

Use the `uid` (user ID) and `gid` (group ID) values to configure the container.

### Initialization Scripts

During container startup, initialization scripts in `/etc/cont-init.d/` are
executed in alphabetical order. They are executed before starting services.

To ensure predictable execution, name scripts using the format `XX-name.sh`,
where `XX` is a sequence number.

The baseimage uses the ranges:

  - 10-29
  - 70-89

Unless specific needs require otherwise, containers built with this baseimage
should use the range 50-59.

### Finalization Scripts

Finalization scripts in `/etc/cont-finish.d/` are executed in alphabetical order
during container shutdown, after all services have stopped.

### Services

Services are background programs managed by the process supervisor, which can be
configured to restart automatically if they terminate.

Services are defined under `/etc/services.d/` in the container. Each service has
its own directory containing files that define its behavior.

The content of these files provides the configuration settings. If a file is
executable, the process supervisor runs it, using its output as the setting's
value.

| File                   | Type             | Description | Default |
|------------------------|------------------|-------------|---------|
| run                    | Program          | The program to run. | N/A |
| is_ready               | Program          | Program to verify if the service is ready. It should exit with code `0` when ready. The service's PID is passed as a parameter. | N/A |
| kill                   | Program          | Program to run when the service needs to be killed. The service's PID is passed as a parameter. The `SIGTERM` signal is sent to the service after execution. | N/A |
| finish                 | Program          | Program invoked when the service terminates. The service's exit code is passed as a parameter. | N/A |
| params                 | String           | Parameters for the service's program, one per line. | No parameter |
| environment            | String           | Environment for the service, with variables in the form `var=value`, one per line. | Environment untouched |
| environment_extra      | String           | Additional variables to add to the environment of the service, one per line, in the form `key=value`. | No extra variable |
| respawn                | Boolean          | Whether the process should be respawned when it terminates. | `FALSE`  |
| sync                   | Boolean          | Whether the process supervisor waits until the service ends. Mutually exclusive with `respawn`. | `FALSE` |
| ready_timeout          | Unsigned integer | Maximum time (in milliseconds) to wait for the service to be ready. | `10000` |
| interval               | Interval         | Interval, in seconds, at which the service should be executed. Mutually exclusive with `respawn`. | No interval |
| uid                    | Unsigned integer | User ID under which the service runs. | `$USER_ID` |
| gid                    | Unsigned integer | Group ID under which the service runs. | `$GROUP_ID` |
| sgid                   | Unsigned integer | List of supplementary group IDs for the service, one per line. | Empty list |
| umask                  | Octal integer    | Umask value (in octal notation) for the service. | `0022` |
| priority               | Signed integer   | Priority at which the service runs. A niceness value of -20 is the highest, and 19 is the lowest. | `0` |
| workdir                | String           | Working directory of the service. | Service's directory path  |
| ignore_failure         | Boolean          | If set, failure to start the service does not prevent the container from starting. | `FALSE` |
| shutdown_on_terminate  | Boolean          | Indicates the container should shut down when the service terminates. | `FALSE` |
| min_running_time       | Unsigned integer | Minimum time (in milliseconds) the service must run before being considered ready. | `500` |
| disabled               | Boolean          | Indicates the service is disabled and will not be loaded or started. | `FALSE` |
| \<service\>.dep        | Boolean          | Indicates the service depends on another service. For example, `srvB.dep` means `srvB` must start first. | N/A |

The following table provides details about some value types:

| Type     | Description |
|----------|-------------|
| Program  | An executable binary, script, or symbolic link to the program to run. The file must have execute permission. |
| Boolean  | A boolean value. A *true* value can be `1`, `true`, `on`, `yes`, `y`, `enable`, or `enabled`. A *false* value can be `0`, `false`, `off`, `no`, `n`, `disable`, or `disabled`. Values are case -insensitive. An empty file indicates a *true* value (i.e., the file can be "touched"). |
| Interval | An unsigned integer value. Also accepted (case-insensitive): `yearly`, `monthly`, `weekly`, `daily`, `hourly`. |

#### Service Group

A service group is a service definition without a `run` program. The process
supervisor loads only its dependencies.

#### Default Service

During startup, the process supervisor first loads the `default` service group,
which includes dependencies for services that should be started and are not
dependencies of the `app` service.

#### Service Readiness

By default, a service is considered ready once it has launched successfully and
ran for at least 500ms.

This behavior can be adjusted by one of these methods:
  - Setting the minimum running time using the `min_running_time` file in the
    service's directory.
  - Adding an `is_ready` program to the service's directory, along with a
    `ready_timeout` file to specify the maximum wait time for readiness.

### Helpers

The baseimage includes helpers that can be used when building a container or
during its execution.

#### Adding/Removing Packages

Use the `add-pkg` and `del-pkg` helpers to add or remove packages, ensuring
proper cleanup to minimize container size.

These tools allow temporary installation of a group of packages (virtual
package)  using the `--virtual NAME` parameter, enabling later removal with
`del-pkg NAME`. Pre-installed packages are ignored and not removed.

Example in a `Dockerfile` for compiling a project:

```dockerfile
RUN \
    add-pkg --virtual build-dependencies build-base cmake git && \
    git clone https://myproject.com/myproject.git && \
    make -C myproject && \
    make -C myproject install && \
    del-pkg build-dependencies
```

If `git` was already installed before adding the virtual package,
`del-pkg build-dependencies` will not remove it.

#### Modifying Files with Sed

The `sed` tool is useful for modifying files during container builds, but it
does not indicate whether changes were made. The `sed-patch` helper provides
patch-like behavior, failing if the `sed` expression does not modify the file:

```shell
sed-patch [SED_OPTIONS]... SED_EXPRESSION FILE
```

Note that the sed option `-i` (edit files in place) is already supplied by the
helper.

Example in a `Dockerfile`:

```dockerfile
RUN sed-patch 's/Replace this/By this/' /etc/myfile
```

If the expression does not change `/etc/myfile`, the command fails, halting the
Docker build.

#### Evaluating Boolean Values

Environment variables are often used to store boolean values. Use
`is-bool-value-true` and `is-bool-value-false` helpers to check these values.

The following values are considered "true":
  - `1`
  - `true`
  - `y`
  - `yes`
  - `enabled`
  - `enable`
  - `on`

The following values are considered "false":
  - `0`
  - `false`
  - `n`
  - `no`
  - `disabled`
  - `disable`
  - `off`

Example to check if `CONTAINER_DEBUG` is true:

```shell
if is-bool-value-true "${CONTAINER_DEBUG:-0}"; then
    # Debug enabled, do something...
fi
```

#### Taking Ownership of a Directory

The `take-ownership` helper recursively sets the user ID and group ID of a
directory and all its files and subdirectories.

This helper is well-suited for scenarios where the directory is mapped to the
host. If the directory is a network share on the host, setting/changing
ownership via `chown` can fail. The helper handles this by ignoring the failure
if a write test is positive.

For example, the following command takes ownership of `/config`, automatically
using the user and group IDs from the `USER_ID` and `GROUP_ID` environment
variables:

```shell
take-ownership /config
```

User and group IDs can also be specified explicitly. The command below sets
the ownership to user ID `99` and group ID `100`:

```shell
take-ownership /config 99 100
```

#### Setting Internal Environment Variables

The `set-cont-env` helper sets internal environment variables from the
`Dockerfile`.

Example to set the `APP_NAME` variable:

```dockerfile
RUN set-cont-env APP_NAME "Xterm"
```

This creates the environment variable file under `/etc/cont-env.d` within the
container.

### Configuration Directory

Applications often need to write configuration, data, states, logs, etc. Inside
the container, such data should be stored under the `/config` directory.

This directory is intended to be mapped to a folder on the host to ensure data
persistence.

> [!NOTE]
> During container startup, ownership of this folder and its contents is set to
> ensure accessibility by the user specified via `USER_ID` and `GROUP_ID`. This
> behavior can be modified using the `TAKE_CONFIG_OWNERSHIP` internal
> environment variable.

#### Application's Data Directories

Many applications use environment variables defined by the
[XDG Base Directory Specification] to determine where to store various data. The
baseimage sets these variables to reside under `/config/`:

  - XDG_DATA_HOME=/config/xdg/data
  - XDG_CONFIG_HOME=/config/xdg/config
  - XDG_CACHE_HOME=/config/xdg/cache
  - XDG_STATE_HOME=/config/xdg/state

[XDG Base Directory Specification]: https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html

### Locales

The default locale of the container is `POSIX`. If this causes issues with your
application, install the appropriate locale. For example, to set the locale to
`en_US.UTF-8`, add these instructions to your `Dockerfile`:

```dockerfile
RUN \
    add-pkg locales && \
    sed-patch 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen
ENV LANG=en_US.UTF-8
```

> [!NOTE]
> Locales are not supported by the musl C standard library on Alpine Linux. See:
>   - http://wiki.musl-libc.org/wiki/Open_Issues#C_locale_conformance
>   - https://github.com/gliderlabs/docker-alpine/issues/144

### Container Log

Outputs (both standard output and standard error) of scripts and programs
executed during the init process and by the process supervisor are available in
the container's log. The container log can be viewed with the command
`docker logs <name of the container>`.

To facilitate log consultationg, all messages are prefixed with the name of the
service or script.

It is advisable to limit the amount of information written to this log. If a
program's output is too verbose, redirect it to a file. For example, the
following `run` file of a service redirects standard output and standard error
to different files:

```shell
#!/bin/sh
exec /usr/bin/my_service > /config/log/my_service_out.log 2> /config/log/my_service_err.log
```
### Logrotate

The baseimage includes `logrotate`, a utility for rotating and compressing log
files, which runs daily via a service. The service is disabled if no log files
are configured.

To enable rotation for a log file, add a configuration file to
`/etc/cont-logrotate.d` within the container. This configuration defines how to
handle the log file.

Example configuration at `/etc/cont-logrotate.d/myapp`:

```text
/config/log/myapp.log {
    minsize 1M
}
```

This file can override default parameters defined at
`/opt/base/etc/logrotate.conf` in the container. By default:
  - Log files are rotated weekly.
  - Four weeks of backlogs are kept.
  - Rotated logs are compressed with gzip.
  - Dates are used as suffixes for rotated logs.

For details on `logrotate` configuration files, see
https://linux.die.net/man/8/logrotate.

### Log Monitor

The baseimage includes a log monitor that sends notifications when specific
messages are detected in log or status files.

The system has two main components:
  - **Notification definitions**: Describe notification properties (title,
    message, severity, etc.), the triggering condition (filtering function), and
    the monitored file(s).
  - **Backends (targets)**: When a matching string is found, a notification is
    sent to one or more backends, which can log to the container, a file, or an
    external service.

Two types of files can be monitored:
  - **Log files**: Files with new content appended.
  - **Status files**: Files whose entire content is periodically
    refreshed/overwritten.

#### Notification Definition

A notification definition consists of multiple files in a directory under
`/etc/logmonitor/notifications.d` within the container. For example, the
definition for `MYNOTIF` is stored in
`/etc/logmonitor/notifications.d/MYNOTIF/`.

The following table describes files part of the definition:

| File     | Mandatory  | Description |
|----------|------------|-------------|
| `filter` | Yes        | Program (script or binary with executable permission) to filter log file messages. It is invoked with a log line as an argument and should exit with `0` on a match. Other values indicate no match. |
| `title`  | Yes        | File containing the notification title. For dynamic content, it can be a program (script or binary with executable permission) invoked with the matched line, using its output as the title. |
| `desc`   | Yes        | File containing the notification description or message. For dynamic content, it can be a program (script or binary with executable permission) invoked with the matched log line, using its output as the description. |
| `level`  | Yes        | File containing the notification's severity level (`ERROR`, `WARNING`, or `INFO`). For dynamic content, it can be a program (script or binary with executable permission) invoked with the matched log line, using its output as the severity. |
| `source` | Yes        | File containing the absolute path(s) to monitored file(s), one per line. Prepend `status:` for status file; `log:` or no prefix indicates a log file. |

#### Notification Backend

A notification backend is defined in a directory under
`/etc/cont-logmonitor/targets.d`. For example, the `stdout` backend is in
`/etc/cont-logmonitor/target.d/stdout/`.

The following table describes the files:

| File         | Mandatory  | Description |
|--------------|------------|-------------|
| `send`       | Yes        | Program (script or binary with executable permission) that sends the notification, invoked with the notification's title, description, and severity level as arguments. |
| `debouncing` | No         | File containing the minimum time (in seconds) before sending the same notification again. A value of `0` means the notification is sent once. If missing, no debouncing occurs. |

The baseimage includes these notification backends:

| Backend  | Description | Debouncing time |
|----------|-------------|-----------------|
| `stdout` | Displays a message to standard output, visible in the container's log, in the format `{LEVEL}: {TITLE} {MESSAGE}`. | 21 600s (6 hours) |
| `yad`    | Displays the notification in a window visible in the application's GUI. | Infinite |

### Accessing the GUI

Assuming the container's ports are mapped to the same host's ports, access the
application's GUI as follows:

  - Via a web browser:

```text
http://<HOST_IP_ADDR>:5800
```

  - Via any VNC client:

```text
<HOST_IP_ADDR>:5900
```

### Security

By default, access to the application's GUI uses an unencrypted connection (HTTP
or VNC).

A secure connection can be enabled via the `SECURE_CONNECTION` environment
variable. See the [Environment Variables](#environment-variables) section for
details on configuring environment variables.

When enabled, the GUI is accessed over HTTPS when using a browser, with all HTTP
accesses redirected to HTTPS.

For VNC clients, the connection can be secured using on of two methods,
configured via the `SECURE_CONNECTION_VNC_METHOD` environment variable:

  - `SSL`: An SSL tunnel is used to transport the VNC connection. Few VNC
    clients supports this method; [SSVNC] is one that does.
  - `TLS`: A VNC security type negotiated during the VNC handshake. It uses TLS
    to establish a secure connection. Clients may optionally validate the
    server’s certificate. Valid certificates must be provided for this
    validation to succeed. See [Certificates](#certificates) for details.
    [TigerVNC] is a client that supports TLS encryption.

[TigerVNC]: https://tigervnc.org

#### SSVNC

[SSVNC] is a VNC viewer that adds encryption to VNC connections by using an
SSL tunnel to transport the VNC traffic.

While the Linux version of [SSVNC] works well, the Windows version has issues.
At the time of writing, the latest version `1.0.30` fails with the error:

```text
ReadExact: Socket error while reading
```

For convenience, an unofficial, working version is provided here:

https://github.com/jlesage/docker-baseimage-gui/raw/master/tools/ssvnc_windows_only-1.0.30-r1.zip

This version upgrades the bundled `stunnel` to version `5.49`, resolving the
connection issues.

[SSVNC]: http://www.karlrunge.com/x11vnc/ssvnc.html

#### Certificates

The following certificate files are required by the container. If missing,
self-signed certificates are generated and used. All files are PEM-encoded x509
certificates.

| Container Path                  | Purpose                    | Content |
|---------------------------------|----------------------------|---------|
|`/config/certs/vnc-server.pem`   |VNC connection encryption.  |VNC server's private key and certificate, bundled with any root and intermediate certificates.|
|`/config/certs/web-privkey.pem`  |HTTPS connection encryption.|Web server's private key.|
|`/config/certs/web-fullchain.pem`|HTTPS connection encryption.|Web server's certificate, bundled with any root and intermediate certificates.|

> [!TIP]
> To avoid certificate validity warnings or errors in browsers or VNC clients,
> provide your own valid certificates.

> [!NOTE]
> Certificate files are monitored, and relevant services are restarted when
> changes are detected.

#### VNC Password

To restrict access to your application, set a password using one of two methods:
  - Via the `VNC_PASSWORD` environment variable.
  - Via a `.vncpass_clear` file at the root of the `/config` volume, containing
    the password in clear text. During container startup, the content is
    obfuscated and moved to `.vncpass`.

The security of the VNC password depends on:
  - The communication channel (encrypted or unencrypted).
  - The security of host access.

When using a VNC password, enable a secure connection to prevent sending the
password in clear text over an unencrypted channel.

Unauthorized users with sufficient host privileges can retrieve the password by:

  - Viewing the `VNC_PASSWORD` environment variable via `docker inspect`. By
    default, the `docker` command requires root access, but it can be configured
    to allow users in a specific group.
  - Decrypting the `/config/.vncpass` file, which requires root or `USER_ID`
    permissions.

> [!CAUTION]
> VNC password is limited to 8 characters. This limitation comes from the Remote
> Framebuffer Protocol [RFC](https://tools.ietf.org/html/rfc6143) (see section
> [7.2.2](https://tools.ietf.org/html/rfc6143#section-7.2.2)).

#### DH Parameters

Diffie-Hellman (DH) parameters define how the [DH key-exchange] is performed.
More details are available on the [OpenSSL Wiki].

DH parameters are stored in the PEM-encoded file at `/config/certs/dhparam.pem`
within the container. If missing, 2048-bit DH parameters are generated
automatically, which is a one-time operation that may significantly increase
container startup time.

[DH key-exchange]: https://en.wikipedia.org/wiki/Diffie%E2%80%93Hellman_key_exchange
[OpenSSL Wiki]: https://wiki.openssl.org/index.php/Diffie_Hellman

#### Web Authentication

Access to the application's GUI via a web browser can be protected with a login
page. When enabled, users must provide valid credentials to gain access.

Enable web authentication by setting the `WEB_AUTHENTICATION` environment
variable to `1`. See the [Environment Variables](#environment-variables) section
for details on configuring environment variables.

> [!IMPORTANT]
> Web authentication requires a secure connection to be enabled. See
> [Security](#security) for details.

##### Configuring User Credentials

User credentials can be configured in two ways:

  1. Via container environment variables.
  2. Via a password database.

Container environment variables provide a quick way to configure a single user.
Set the username and password using:
  - `WEB_AUTHENTICATION_USERNAME`
  - `WEB_AUTHENTICATION_PASSWORD`

See the [Environment Variables](#environment-variables) section for details on
configuring environment variables.

For a more secure method or to configure multiple users, use a password database
at `/config/webauth-htpasswd` within the container. This file uses the Apache
HTTP server's htpasswd format, storing bcrypt-hashed passwords.

Manage users with the `webauth-user` tool:
  - Add a user: `docker exec -ti <container name> webauth-user add <username>`
  - Update a user: `docker exec -ti <container name> webauth-user update <username>`
  - Remove a user: `docker exec <container name> webauth-user del <username>`
  - List users: `docker exec <container name> webauth-user list`

### Reverse Proxy

The following sections provide NGINX configurations for setting up a reverse
proxy to a container built with this baseimage.

A reverse proxy server can route HTTP requests based on the hostname or URL
path.

#### Routing Based on Hostname

In this scenario, each hostname is routed to a different application or
container.

For example, if the reverse proxy server runs on the same machine as this
container, it would proxy all HTTP requests for `myapp.domain.tld` to
the container at `127.0.0.1:5800`.

Here are the relevant configuration elements to add to the NGINX configuration:

```nginx
map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
}

upstream docker-myapp {
        # If the reverse proxy server is not running on the same machine as the
        # Docker container, use the IP of the Docker host here.
        # Make sure to adjust the port according to how port 5800 of the
        # container has been mapped on the host.
        server 127.0.0.1:5800;
}

server {
        [...]

        server_name myapp.domain.tld;

        location / {
                proxy_pass http://docker-myapp;
        }

        location /websockify {
                proxy_pass http://docker-myapp;
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection $connection_upgrade;
                proxy_read_timeout 86400;
        }

        # Needed when audio support is enabled.
        location /websockify-audio {
                proxy_pass http://docker-myapp;
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection $connection_upgrade;
                proxy_read_timeout 86400;
        }
}

```

#### Routing Based on URL Path

In this scenario, the same hostname is used, but different URL paths route to
different applications or containers. For example, if the reverse proxy server
runs on the same machine as this container, it would proxy all HTTP requests for
`server.domain.tld/filebot` to the container at `127.0.0.1:5800`.

Here are the relevant configuration elements to add to the NGINX configuration:

```nginx
map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
}

upstream docker-myapp {
        # If the reverse proxy server is not running on the same machine as the
        # Docker container, use the IP of the Docker host here.
        # Make sure to adjust the port according to how port 5800 of the
        # container has been mapped on the host.
        server 127.0.0.1:5800;
}

server {
        [...]

        location = /myapp {return 301 $scheme://$http_host/myapp/;}
        location /myapp/ {
                proxy_pass http://docker-myapp/;
                # Uncomment the following line if your Nginx server runs on a port that
                # differs from the one seen by external clients.
                #port_in_redirect off;
                location /myapp/websockify {
                        proxy_pass http://docker-myapp/websockify;
                        proxy_http_version 1.1;
                        proxy_set_header Upgrade $http_upgrade;
                        proxy_set_header Connection $connection_upgrade;
                        proxy_read_timeout 86400;
                }
        }
}

```

### Web Audio

The baseimage supports streaming audio from applications using PulseAudio,
played through the user's web browser. Audio is not supported for VNC clients.

Audio is streamed with the following specifications:
  - Raw PCM format
  - 2 channels
  - 16-bit sample depth
  - 44.1kHz sample rate

Enable web audio by setting `WEB_AUDIO` to `1`. See the
[Environment Variables](#environment-variables) section for details on
configuring environment variables.

Once enabled, the PulseAudio environment is configured for the application, and
additional services start to capture and stream audio.

### Web File Manager

The baseimage includes a simple file manager for interacting with container
files through a web browser, supporting operations like renaming, deleting,
uploading, and downloading.

Enable the file manager by setting `WEB_FILE_MANAGER` to `1`. See the
[Environment Variables](#environment-variables) section for details on
configuring environment variables.

By default, the container's entire filesystem is not accessible. The
`WEB_FILE_MANAGER_ALLOWED_PATHS` environment variable is a comma-separated list
that specifies which paths within the container are allowed to be accessed. When
set to `AUTO` (the default), it automatically includes commonly used folders and
any folders mapped to the container.

The `WEB_FILE_MANAGER_DENIED_PATHS` environment variable defines which paths are
explicitly denied access by the file manager. A denied path takes precedence
over an allowed one.

### Application Icon

An icon for your application can be added to the image. It is used by different
features of the web interface and to generate favicons.

Add the following command to your `Dockerfile`, specifying the URL to your
master icon. The master icon should be a square PNG image with a size of at
least 512x512 for optimal results.

```dockerfile
# Generate and install favicons.
RUN \
    APP_ICON_URL=https://github.com/jlesage/docker-templates/raw/master/jlesage/images/generic-app-icon.png && \
    install_app_icon.sh "$APP_ICON_URL"
```

### Dark Mode

Dark mode can be enabled via the `DARK_MODE` environment variable. When enabled,
the web interface used to display the application is automatically adjusted
accordingly.

Supporting dark mode for the application itself is more complex, as applications
use different toolkits to build their UI, each with its own method to activate
dark mode.

The baseimage supports the [GTK] and [Qt] toolkits.

[GTK]: https://www.gtk.org
[Qt]: https://www.qt.io

#### GTK

When dark mode is enabled, the baseimage automatically configures the
environment to apply a dark theme to the application. This is achieved by
setting the following environment variables:

  - `GTK_THEME` is set to `Adwaita:dark`. This is used by GTK3 and GTK4
    applications.
  - `GTK2_RC_FILES` is set to `/opt/base/share/themes/Dark/gtk-2.0/gtkrc`. This
    is used by GTK2 applications.

#### Qt

When dark mode is enabled, the baseimage automatically configures the
environment to apply a dark theme to the application. This is done by setting
the `QT_STYLE_OVERRIDE` environment variable to `Adwaita-Dark`.

Additionally, the application's `Dockerfile` must install the Adwaita theme,
provided by the `adwaita-qt` package, available in the Ubuntu, Debian, or Alpine
Linux software repositories.

> [!NOTE]
> Dark mode is supported for Qt5 and Qt6.

### Tips and Best Practices

#### Do Not Modify Baseimage Content

Avoid modifying files provided by the baseimage to minimize issues when
upgrading to newer versions.

#### Default Configuration Files

Retaining the original version of application configuration files is often
helpful. This allows an initialization script to modify a file based on its
original version.

These original files, also called default files, should be stored under the
`/defaults` directory inside the container.

#### The $HOME Variable

The application runs under a Linux user with a specified ID, without login
capability, password, valid shell, or home directory, similar to a daemon user.

By default, the `$HOME` environment variable is unset. Some applications expect
`$HOME` to be set and may not function correctly otherwise.

To address this, set the home directory in the `startapp.sh` script:

```shell
export HOME=/config
```

Adjust the location as needed. If the application writes to the home directory,
use a directory mapped to the host (like `/config`).

This technique can also be applied to services by setting the home directory in
their `run` script.

#### Referencing Linux User/Group

Reference the Linux user/group running the application via:
  - Their IDs, specified by `USER_ID`/`GROUP_ID` environment variables.
  - The `app` user/group, set up during startup to match `USER_ID`/`GROUP_ID`.

#### Using `rootfs` Directory

Store files to be copied into the container in the `rootfs` directory in your
source tree, mirroring the container's structure. For example,
`/etc/cont-init.d/my-init.sh` in the container should be
`rootfs/etc/cont-init.d/my-init.sh` in your source tree.

Copy all files with a single `Dockerfile` command:

```dockerfile
COPY rootfs/ /
```

#### Maximizing Only the Main Window

By default, the application's window is maximized, and decorations are hidden.
For applications with multiple windows, this behavior may need to be applied
only to the main window.

The window manager can be configured to apply different behaviors to different
windows of the application. A specific window is identified by matching one or
more of its properties:

  - Name of the window
  - Class of the window
  - Title of the window
  - Type of the window
  - etc.

To find a window's properties:
  - Create and start an instance of the container.
  - From the host, run the `obxprop` tool:
```shell
docker exec <container name> obxprop | grep "^_OB_APP"
```
  - Access the GUI and click the target window to display its properties.

The following table shows how to find relevant properties:

| Property   | Value |
|------------|-------|
| Name       | The window's `_OB_APP_NAME` property. |
| Class      | The window's `_OB_APP_CLASS` property. |
| Title      | The window's `_OB_APP_TITLE` property. |
| GroupName  | The window's `_OB_APP_GROUP_NAME` property. |
| GroupClass | The window's `_OB_APP_GROUP_CLASS` property. |
| Type       | The window's `_OB_APP_TYPE` property. Values: `desktop`, `dialog`, `dock`, `menu`, `normal`, `notification`, `splash`, `toolbar`, `utility`. |
| Role       | The window's `_OB_APP_ROLE` property. |

By default, the window manager matches only the `normal` window type. Add more
criteria to select the correct window by creating a file at
`/etc/openbox/main-window-selection.xml` (in the container) with one criterion
per line in XML format. Example to match type and name:

```xml
<Type>normal</Type>
<Name>My Application</Name>
```

> [!NOTE]
> For backward compatibility with previous 4.x versions, the container falls
> back to `/etc/jwm/main-window-selection.jwmrc` if
> `/etc/openbox/main-window-selection.xml` does not exist.

#### Adaptations from Version 3.x
When updating from version 3.x, consider the following:

  - Review exposed environment variables to categorize them as public or
    internal. See [Environment Variables](#environment-variables).
  - Rename initialization scripts to follow the `XX-name.sh` format. See
    [Initialization Scripts](#initialization-scripts).
  - Adjust service parameters/definitions for the new system. See
    [Services](#services).
  - Ensure no scripts use `with-contenv` in their shebang (e.g., in init
    scripts).
  - Set `APP_VERSION` and `DOCKER_IMAGE_VERSION` internal environment variables
    if needed.
  - Adapt window manager configurations (e.g., for maximizing the main window)
    to the new mechanism. See
    [Maximizing Only the Main Window](#maximizing-only-the-main-window).

