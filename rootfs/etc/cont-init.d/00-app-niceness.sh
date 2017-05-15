#!/usr/bin/with-contenv sh

#
# Handle configured niceness value of the application.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

APP_NICE_CMD=' '

if [ "${APP_NICENESS:-UNSET}" != "UNSET" ]; then
    APP_NICE_CMD="$(which nice) -n $APP_NICENESS"

    # NOTE: On debian systems, nice always has an exit code of `0`, even when
    # permission is denied.  Look for the error message instead.
    if [ "$($APP_NICE_CMD true 2>&1)" != "" ]; then
        echo "ERROR: Permission denied to set application's niceness to" \
             "$APP_NICENESS.  Make sure the container is started with the" \
             "--cap-add=SYS_NICE option."
        exit 6
    fi
fi

# Export variable.
echo "$APP_NICE_CMD" > /var/run/s6/container_environment/APP_NICE_CMD

# vim: set ft=sh :
