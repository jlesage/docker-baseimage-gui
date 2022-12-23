#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

mkdir -p /var/run/openbox
chown $USER_ID:$GROUP_ID /var/run/openbox

#
# Setup the Openbox theme.
#
mkdir -p "$XDG_DATA_HOME"/themes
if is-bool-val-true "${DARK_MODE:-0}"; then
    ln -sfn /opt/base/share/themes/Dark "$XDG_DATA_HOME"/themes/OpenboxTheme
else
    ln -sfn /opt/base/share/themes/Light "$XDG_DATA_HOME"/themes/OpenboxTheme
fi

#
# Setup selection of the main window.
#

APP_DEF_FILE="$(mktemp)"
APP_DEF_NAME=
APP_DEF_CLASS=
APP_DEF_GROUP_NAME=
APP_DEF_GROUP_CLASS=
APP_DEF_ROLE=
APP_DEF_TITLE=
APP_DEF_TYPE=

set_app_def_vars() {
    F="$1"

    APP_DEF_NAME="$(cat "$F" | awk -F "[><]" '/Name/{print $3}')"
    APP_DEF_CLASS="$(cat "$F" | awk -F "[><]" '/Class/{print $3}')"
    APP_DEF_GROUP_NAME="$(cat "$F" | awk -F "[><]" '/GroupName/{print $3}')"
    APP_DEF_GROUP_CLASS="$(cat "$F" | awk -F "[><]" '/GroupClass/{print $3}')"
    APP_DEF_ROLE="$(cat "$F" | awk -F "[><]" '/Role/{print $3}')"
    APP_DEF_TITLE="$(cat "$F" | awk -F "[><]" '/Title/{print $3}')"
    APP_DEF_TYPE="$(cat "$F" | awk -F "[><]" '/Type/{print $3}')"

    # If using the JWM config, remove the begining `^` and ending `$` regex
    # characters, because they are not supported by OpenBox.
    if [ "$F" = /etc/jwm/main-window-selection.jwmrc ]; then
        APP_DEF_NAME="$(echo "$APP_DEF_NAME" | sed 's/^\^//' | sed 's/\$$//')"
        APP_DEF_CLASS="$(echo "$APP_DEF_CLASS" | sed 's/^\^//' | sed 's/\$$//')"
        APP_DEF_GROUP_NAME="$(echo "$APP_DEF_GROUP_NAME" | sed 's/^\^//' | sed 's/\$$//')"
        APP_DEF_GROUP_CLASS="$(echo "$APP_DEF_GROUP_CLASS" | sed 's/^\^//' | sed 's/\$$//')"
        APP_DEF_ROLE="$(echo "$APP_DEF_ROLE" | sed 's/^\^//' | sed 's/\$$//')"
        APP_DEF_TITLE="$(echo "$APP_DEF_TITLE" | sed 's/^\^//' | sed 's/\$$//')"
        APP_DEF_TYPE="$(echo "$APP_DEF_TYPE" | sed 's/^\^//' | sed 's/\$$//')"
    fi
}

if [ -f /etc/openbox/main-window-selection.xml ]; then
    set_app_def_vars /etc/openbox/main-window-selection.xml
elif [ -f /etc/jwm/main-window-selection.jwmrc ]; then
    set_app_def_vars /etc/jwm/main-window-selection.jwmrc
else
    APP_DEF_TYPE=normal
fi

# Generate the application definitions block.
echo "  <application" >> "$APP_DEF_FILE"
if [ -n "$APP_DEF_NAME" ]; then
    echo "    name=\"$APP_DEF_NAME\"" >> "$APP_DEF_FILE"
fi
if [ -n "$APP_DEF_CLASS" ]; then
    echo "    class=\"$APP_DEF_CLASS\"" >> "$APP_DEF_FILE"
fi
if [ -n "$APP_DEF_GROUP_NAME" ]; then
    echo "    groupname=\"$APP_DEF_GROUP_NAME\"" >> "$APP_DEF_FILE"
fi
if [ -n "$APP_DEF_GROUP_CLASS" ]; then
    echo "    groupclass=\"$APP_DEF_GROUP_CLASS\"" >> "$APP_DEF_FILE"
fi
if [ -n "$APP_DEF_ROLE" ]; then
    echo "    role=\"$APP_DEF_ROLE\"" >> "$APP_DEF_FILE"
fi
if [ -n "$APP_DEF_TITLE" ]; then
    echo "    title=\"$APP_DEF_TITLE\"" >> "$APP_DEF_FILE"
fi
if [ -n "$APP_DEF_TYPE" ]; then
    echo "    type=\"$APP_DEF_TYPE\"" >> "$APP_DEF_FILE"
fi
echo "  >" >> "$APP_DEF_FILE"
echo "    <decor>no</decor>" >> "$APP_DEF_FILE"
echo "    <maximized>true</maximized>" >> "$APP_DEF_FILE"
echo "    <layer>below</layer>" >> "$APP_DEF_FILE"
echo "  </application>" >> "$APP_DEF_FILE"

# Write the final Openbox config file.
cat /opt/base/etc/openbox/rc.xml.template | sed -e '/MAIN_APP_WINDOW_DEF/ {' -e "r $APP_DEF_FILE" -e 'd' -e '}' > /var/run/openbox/rc.xml

# vim:ft=sh:ts=4:sw=4:et:sts=4