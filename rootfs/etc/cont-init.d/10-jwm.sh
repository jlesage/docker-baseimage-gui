#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

#
# Make sure required directories exist.
#
JWM_DIRS="\
    /var/run/jwm \
"

for DIR in $JWM_DIRS
do
    mkdir -p "$DIR"
    chown $USER_ID:$GROUP_ID "$DIR"
done

# vim:ft=sh:ts=4:sw=4:et:sts=4
