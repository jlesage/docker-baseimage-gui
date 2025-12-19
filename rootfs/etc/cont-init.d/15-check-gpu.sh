#!/bin/sh
#
# Find and report issues that would prevent usage of the GPU.
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

DRI_DIR="/dev/dri"

permissions_ok() {
    DEV_UID="$(stat -c "%u" "$1")"
    DEV_GID="$(stat -c "%g" "$1")"

    DEV_PERM="$(stat -c "%a" "$1")"
    DEV_PERM_U="$(echo "$DEV_PERM" | head -c 1 | tail -c 1)"
    DEV_PERM_G="$(echo "$DEV_PERM" | head -c 2 | tail -c 1)"
    DEV_PERM_O="$(echo "$DEV_PERM" | head -c 3 | tail -c 1)"

    # OK: User permission of the device is R/W and the container runs as root.
    [ "$DEV_PERM_U" -ge 6 ] && [ "$USER_ID" = "0" ] && return 0

    # OK: User permission of the device is R/W and user matches the container
    #     user.
    [ "$DEV_PERM_U" -ge 6 ] && [ "$DEV_UID" = "$USER_ID" ] && return 0

    # OK: The group permission of the device is R/W and group maches the
    #     container group.
    [ "$DEV_PERM_G" -ge 6 ] && [ "$DEV_GID" = "$GROUP_ID" ] && return 0

    # OK: The group permission of the device is R/W and group is not root,
    #     meaning that a supplementary group can be automatically added.
    [ "$DEV_PERM_G" -ge 6 ] && [ "$DEV_GID" != "0" ] && return 0

    # OK: The other permission of the device is R/W.
    [ "$DEV_PERM_O" -ge 6 ] && return 0

    return 1
}

write_access_test() {
    [ -e "$1" ] || return 1
    output="$(2>&1 >> "$1")"
    rc=$?
    if [ $rc -ne 0 ]; then
        if ! echo "$output" | grep -iq "permission denied"; then
            # We just want error related to the lack of write permission.
            rc=0
        fi
    fi
    return $rc
}

using_initial_user_namespace() {
    [ "$(cat /proc/self/uid_map | xargs)" = "0 0 4294967295" ]
}

if [ ! -d "$DRI_DIR" ]; then
    echo "Hardware acceleration via GPU not supported: device directory $DRI_DIR not exposed to the container."
    exit 0
fi

gpu_node_found=false
render_node_found=false

while read -r f; do
    [ -n "$f" ] || continue
    [ -c "$f" ] || continue
    if permissions_ok "${f}"; then
        echo "  [ OK ]   the device ${f} has proper permissions."
        is-bool-val-false "${CONTAINER_DEBUG:-0}" || echo "           permissions: $(ls -l "${f}" | awk '{print $1,$3,$4}')"
        if write_access_test "${f}"; then
            echo "  [ OK ]   the container can write to device ${f}."
        else
            echo "  [ ERR ]  the container cannot write to device ${f}."
            using_initial_user_namespace || echo "           problem might be caused by improper user namespace configuration."
        fi
    else
            echo "  [ ERR ]  the device ${f} does not have proper permissions."
            is-bool-val-false "${CONTAINER_DEBUG:-0}" || echo "           permissions: $(ls -l "${f}" | awk '{print $1,$3,$4}')"
    fi
    case "${f}" in
        /dev/dri/card*) gpu_node_found=true ;;
        /dev/dri/renderD*) render_node_found=true ;;
    esac
done <<EOF
$(find "$DRI_DIR" -mindepth 1 -maxdepth 1)
EOF

if $gpu_node_found; then
    echo "  [ OK ]   a GPU node has been found."
else
    echo "  [ ERR ]  no GPU node found."
fi

if $render_node_found; then
    echo "  [ OK ]   a render node has been found."
else
    echo "  [ ERR ]  no render node found."
fi

# vim:ft=sh:ts=4:sw=4:et:sts=4
