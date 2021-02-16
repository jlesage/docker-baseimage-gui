#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Since Xvnc is not running as root, we need to create /tmp/.X11-unix before
# it starts to avoid complains.
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
