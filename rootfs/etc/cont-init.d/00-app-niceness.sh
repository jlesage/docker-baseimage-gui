#!/usr/bin/with-contenv sh

#
# Handle configured niceness value of the application.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

APP_NICE_CMD=' '

if [ "${APP_NICENESS:-UNSET}" != "UNSET" ]; then
    APP_NICE_CMD="nice -n $APP_NICENESS"

    if ! $APP_NICE_CMD echo &> /dev/null; then
        echo "ERROR: Permission denied to set application's niceness to" \
             "$APP_NICENESS.  Make sure the container is started with the" \
             "--cap-add=SYS_NICE option."
        exit 6
    fi
fi

# Export variable.
echo "$APP_NICE_CMD" > /var/run/s6/container_environment/APP_NICE_CMD

# vim: set ft=sh :
