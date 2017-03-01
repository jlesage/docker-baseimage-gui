#!/usr/bin/with-contenv sh

#
# Make sure the startapp.sh has execution permission.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

if [ -e /startapp.sh ] ; then
    chmod a+rx /startapp.sh
fi

# vim: set ft=sh :
