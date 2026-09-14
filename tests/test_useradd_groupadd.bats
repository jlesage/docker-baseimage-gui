#!/bin/env bats

# Account databases (/etc/passwd, /etc/group, /etc/shadow) are symlinks in this
# baseimage. These tests verify that useradd/groupadd operate correctly in that
# setup (including preserving the symlinks), and that useradd -K (login.defs
# key overrides) works as used by package scripts.

setup() {
    load setup_common
    load setup_container_daemon
}

teardown() {
    load teardown_container_daemon
    load teardown_common
}

dump_daemon_logs() {
    echo "====================================================================="
    echo " DOCKER LOGS"
    echo "====================================================================="
    getlog_container_daemon
    echo "====================================================================="
    echo " END DOCKER LOGS"
    echo "====================================================================="
}

# Skip when useradd is not available in the image.
require_useradd() {
    if ! exec_container_daemon sh -c "command -v useradd" >/dev/null 2>&1; then
        skip "useradd is not available in this image"
    fi
}

# Skip when groupadd is not available in the image.
require_groupadd() {
    if ! exec_container_daemon sh -c "command -v groupadd" >/dev/null 2>&1; then
        skip "groupadd is not available in this image"
    fi
}

# Skip when the multicall account-management binary is not installed.
require_shadow_tools() {
    if ! exec_container_daemon sh -c "command -v useradd && command -v chage" >/dev/null 2>&1; then
        skip "account management tools are not available in this image"
    fi
}

# Assert that account databases are currently symlinks (the baseimage layout).
assert_databases_are_symlinks() {
    run exec_container_daemon sh -c "test -L /etc/passwd"
    echo "passwd is symlink: $status"
    [ "$status" -eq 0 ]

    run exec_container_daemon sh -c "test -L /etc/group"
    echo "group is symlink: $status"
    [ "$status" -eq 0 ]

    run exec_container_daemon sh -c "test -L /etc/shadow"
    echo "shadow is symlink: $status"
    [ "$status" -eq 0 ]
}

@test "Checking that /usr/bin account tools resolve to the same binary as /usr/sbin..." {
    dump_daemon_logs
    require_shadow_tools

    # Package maintainer scripts often call /usr/bin/chage (etc.) with an
    # absolute path. Those must not remain the distro binaries when a
    # replacement under /usr/sbin is installed.
    for tool in chage passwd chfn chsh newgrp gpasswd sg expiry newuidmap newgidmap; do
        run exec_container_daemon sh -c "
            if [ -e /usr/bin/$tool ] || [ -L /usr/bin/$tool ]; then
                bin=\$(readlink -f /usr/bin/$tool)
                sbin=\$(readlink -f /usr/sbin/$tool)
                echo \"/usr/bin/$tool -> \$bin\"
                echo \"/usr/sbin/$tool -> \$sbin\"
                [ -n \"\$bin\" ] && [ \"\$bin\" = \"\$sbin\" ]
            else
                echo \"/usr/bin/$tool not present; skipped\"
            fi
        "
        echo "$output"
        [ "$status" -eq 0 ]
    done
}

@test "Checking that gpasswd -a works when group database is a symlink..." {
    dump_daemon_logs
    require_shadow_tools

    run exec_container_daemon sh -c "command -v gpasswd"
    if [ "$status" -ne 0 ]; then
        skip "gpasswd is not available in this image"
    fi

    run exec_container_daemon sh -c "test -L /etc/group"
    [ "$status" -eq 0 ]

    run exec_container_daemon sh -c "readlink /etc/group"
    [ "$status" -eq 0 ]
    GROUP_TARGET="$output"

    # Create a disposable group and user for membership tests.
    run exec_container_daemon groupadd -g 6300 gpassgrp
    echo "groupadd: $status $output"
    [ "$status" -eq 0 ]

    run exec_container_daemon useradd -u 6300 -g 0 -M -N -s /usr/sbin/nologin gpassuser
    echo "useradd: $status $output"
    [ "$status" -eq 0 ]

    run exec_container_daemon gpasswd -a gpassuser gpassgrp
    echo "gpasswd -a: $status $output"
    [ "$status" -eq 0 ]

    run exec_container_daemon sh -c "test -L /etc/group"
    echo "group still symlink: $status"
    [ "$status" -eq 0 ]

    run exec_container_daemon sh -c "readlink /etc/group"
    [ "$status" -eq 0 ]
    [ "$output" = "$GROUP_TARGET" ]

    run exec_container_daemon sh -c "grep -E '^gpassgrp:x:6300:.*gpassuser' /etc/group"
    echo "membership: $status $output"
    [ "$status" -eq 0 ]

    run exec_container_daemon sh -c "grep -E '^gpassgrp:x:6300:.*gpassuser' '$GROUP_TARGET'"
    echo "real group membership: $status"
    [ "$status" -eq 0 ]
}

@test "Checking that user and group databases are symlinks..." {
    dump_daemon_logs

    # Account databases are stored outside the container filesystem.
    assert_databases_are_symlinks

    # gshadow is optional.
    run exec_container_daemon sh -c "if [ -e /etc/gshadow ]; then test -L /etc/gshadow; else true; fi"
    echo "gshadow is symlink or absent: $status"
    [ "$status" -eq 0 ]

    # Symlinks should point under /tmp (runtime data).
    run exec_container_daemon sh -c "readlink /etc/passwd"
    echo "passwd -> $output"
    [ "$status" -eq 0 ]
    [[ "$output" == /tmp/* ]]

    run exec_container_daemon sh -c "readlink /etc/group"
    echo "group -> $output"
    [ "$status" -eq 0 ]
    [[ "$output" == /tmp/* ]]

    run exec_container_daemon sh -c "readlink /etc/shadow"
    echo "shadow -> $output"
    [ "$status" -eq 0 ]
    [[ "$output" == /tmp/* ]]
}

@test "Checking that useradd works when databases are symlinks..." {
    dump_daemon_logs
    require_useradd

    # Capture targets before the operation.
    run exec_container_daemon sh -c "readlink /etc/passwd"
    [ "$status" -eq 0 ]
    PASSWD_TARGET="$output"
    run exec_container_daemon sh -c "readlink /etc/group"
    [ "$status" -eq 0 ]
    GROUP_TARGET="$output"
    run exec_container_daemon sh -c "readlink /etc/shadow"
    [ "$status" -eq 0 ]
    SHADOW_TARGET="$output"

    # -M: no home, -N: no matching group, -u/-g: fixed ids for easy checks.
    run exec_container_daemon useradd -u 6200 -g 0 -M -N -s /usr/sbin/nologin testuseradd
    echo "useradd status: $status"
    echo "$output"
    [ "$status" -eq 0 ]

    # Databases must still be the same symlinks.
    assert_databases_are_symlinks

    run exec_container_daemon sh -c "readlink /etc/passwd"
    [ "$status" -eq 0 ]
    [ "$output" = "$PASSWD_TARGET" ]

    run exec_container_daemon sh -c "readlink /etc/group"
    [ "$status" -eq 0 ]
    [ "$output" = "$GROUP_TARGET" ]

    run exec_container_daemon sh -c "readlink /etc/shadow"
    [ "$status" -eq 0 ]
    [ "$output" = "$SHADOW_TARGET" ]

    # Entry visible via the symlink path.
    run exec_container_daemon sh -c "grep -q '^testuseradd:x:6200:0:' /etc/passwd"
    echo "passwd entry: $status"
    [ "$status" -eq 0 ]

    run exec_container_daemon sh -c "grep -q '^testuseradd:' /etc/shadow"
    echo "shadow entry: $status"
    [ "$status" -eq 0 ]

    # Entry also written to the real file behind the symlink.
    run exec_container_daemon sh -c "grep -q '^testuseradd:x:6200:0:' '$PASSWD_TARGET'"
    echo "real passwd entry: $status"
    [ "$status" -eq 0 ]
}

@test "Checking that groupadd works when databases are symlinks..." {
    dump_daemon_logs
    require_groupadd

    run exec_container_daemon sh -c "readlink /etc/group"
    [ "$status" -eq 0 ]
    GROUP_TARGET="$output"

    run exec_container_daemon groupadd -g 6201 testgroupadd
    echo "groupadd status: $status"
    echo "$output"
    [ "$status" -eq 0 ]

    run exec_container_daemon sh -c "test -L /etc/group"
    echo "group still symlink: $status"
    [ "$status" -eq 0 ]

    run exec_container_daemon sh -c "readlink /etc/group"
    [ "$status" -eq 0 ]
    [ "$output" = "$GROUP_TARGET" ]

    run exec_container_daemon sh -c "grep -q '^testgroupadd:x:6201:' /etc/group"
    echo "group entry: $status"
    [ "$status" -eq 0 ]

    run exec_container_daemon sh -c "grep -q '^testgroupadd:x:6201:' '$GROUP_TARGET'"
    echo "real group entry: $status"
    [ "$status" -eq 0 ]
}

@test "Checking that useradd -K overrides login.defs UID range..." {
    dump_daemon_logs
    require_useradd

    assert_databases_are_symlinks

    # Force allocation into a narrow, unused UID window via -K.
    run exec_container_daemon useradd -K UID_MIN=9100 -K UID_MAX=9100 -M -N -s /usr/sbin/nologin keyuser
    echo "useradd -K status: $status"
    echo "$output"
    [ "$status" -eq 0 ]

    run exec_container_daemon sh -c "grep -q '^keyuser:x:9100:' /etc/passwd"
    echo "keyuser UID 9100: $status"
    [ "$status" -eq 0 ]

    # Databases must remain symlinks after -K path as well.
    assert_databases_are_symlinks
}

@test "Checking that useradd --key works the same as -K..." {
    dump_daemon_logs
    require_useradd

    run exec_container_daemon useradd --key UID_MIN=9101 --key UID_MAX=9101 -M -N -s /usr/sbin/nologin keyuserlong
    echo "useradd --key status: $status"
    echo "$output"
    [ "$status" -eq 0 ]

    run exec_container_daemon sh -c "grep -q '^keyuserlong:x:9101:' /etc/passwd"
    echo "keyuserlong UID 9101: $status"
    [ "$status" -eq 0 ]
}

@test "Checking that useradd -K works for system accounts..." {
    dump_daemon_logs
    require_useradd

    # System range override (SYS_UID_MIN/MAX) used by package maintainer scripts.
    run exec_container_daemon useradd -r -K SYS_UID_MIN=250 -K SYS_UID_MAX=250 -M -N -s /usr/sbin/nologin syskeyuser
    echo "useradd -r -K status: $status"
    echo "$output"
    [ "$status" -eq 0 ]

    run exec_container_daemon sh -c "grep -q '^syskeyuser:x:250:' /etc/passwd"
    echo "syskeyuser UID 250: $status"
    [ "$status" -eq 0 ]
}

@test "Checking that useradd -K with user group honors GID overrides..." {
    dump_daemon_logs
    require_useradd

    # Without -N, useradd creates a matching group; GID range comes from -K too.
    run exec_container_daemon useradd \
        -K UID_MIN=9200 -K UID_MAX=9200 \
        -K GID_MIN=9200 -K GID_MAX=9200 \
        -M -s /usr/sbin/nologin keygrpuser
    echo "useradd -K user-group status: $status"
    echo "$output"
    [ "$status" -eq 0 ]

    run exec_container_daemon sh -c "grep -q '^keygrpuser:x:9200:9200:' /etc/passwd"
    echo "passwd UID/GID 9200: $status"
    [ "$status" -eq 0 ]

    run exec_container_daemon sh -c "grep -q '^keygrpuser:x:9200:' /etc/group"
    echo "group GID 9200: $status"
    [ "$status" -eq 0 ]

    run exec_container_daemon sh -c "test -L /etc/passwd && test -L /etc/group"
    echo "still symlinks: $status"
    [ "$status" -eq 0 ]
}

# vim:ft=sh:ts=4:sw=4:et:sts=4
