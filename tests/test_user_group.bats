#!/bin/env bats

setup() {
    load setup_common

    # Custom group definitions under /etc/cont-groups.d.
    mkdir -p "$TESTS_WORKDIR"/cont-groups.d/{mygrp,renamedgrp,disabledgrp,scriptgrp}

    echo "5100" > "$TESTS_WORKDIR"/cont-groups.d/mygrp/id

    echo "5101" > "$TESTS_WORKDIR"/cont-groups.d/renamedgrp/id
    echo "othergrp" > "$TESTS_WORKDIR"/cont-groups.d/renamedgrp/name

    echo "5102" > "$TESTS_WORKDIR"/cont-groups.d/disabledgrp/id
    # Empty boolean file means true (disabled).
    touch "$TESTS_WORKDIR"/cont-groups.d/disabledgrp/disabled

    cat << 'EOF' > "$TESTS_WORKDIR"/cont-groups.d/scriptgrp/id
#!/bin/sh
echo 5103
EOF
    chmod a+rx "$TESTS_WORKDIR"/cont-groups.d/scriptgrp/id

    # Custom user definitions under /etc/cont-users.d.
    mkdir -p "$TESTS_WORKDIR"/cont-users.d/{myuser,renameduser,disableduser,hashuser,passuser,scriptuser}

    echo "6100" > "$TESTS_WORKDIR"/cont-users.d/myuser/id
    echo "5100" > "$TESTS_WORKDIR"/cont-users.d/myuser/gid
    echo "/tmp/myhome" > "$TESTS_WORKDIR"/cont-users.d/myuser/home
    printf "mygrp\ncinit\n" > "$TESTS_WORKDIR"/cont-users.d/myuser/grps

    echo "6101" > "$TESTS_WORKDIR"/cont-users.d/renameduser/id
    echo "5100" > "$TESTS_WORKDIR"/cont-users.d/renameduser/gid
    echo "otheruser" > "$TESTS_WORKDIR"/cont-users.d/renameduser/name

    echo "6102" > "$TESTS_WORKDIR"/cont-users.d/disableduser/id
    echo "5100" > "$TESTS_WORKDIR"/cont-users.d/disableduser/gid
    echo "1" > "$TESTS_WORKDIR"/cont-users.d/disableduser/disabled

    # Pre-computed password hash for a known password.
    PASSWORD_HASH="$(docker run --rm "$DOCKER_IMAGE" sh -c 'printf %s secretpass | /opt/base/bin/mkpasswd')"
    echo "6103" > "$TESTS_WORKDIR"/cont-users.d/hashuser/id
    echo "5100" > "$TESTS_WORKDIR"/cont-users.d/hashuser/gid
    printf "%s" "$PASSWORD_HASH" > "$TESTS_WORKDIR"/cont-users.d/hashuser/password_hash
    # Persist for assertions in tests.
    printf "%s" "$PASSWORD_HASH" > "$TESTS_WORKDIR"/expected_password_hash

    echo "6104" > "$TESTS_WORKDIR"/cont-users.d/passuser/id
    echo "5100" > "$TESTS_WORKDIR"/cont-users.d/passuser/gid
    printf "%s" "secretpass" > "$TESTS_WORKDIR"/cont-users.d/passuser/password

    cat << 'EOF' > "$TESTS_WORKDIR"/cont-users.d/scriptuser/id
#!/bin/sh
echo 6105
EOF
    cat << 'EOF' > "$TESTS_WORKDIR"/cont-users.d/scriptuser/gid
#!/bin/sh
echo 5100
EOF
    cat << 'EOF' > "$TESTS_WORKDIR"/cont-users.d/scriptuser/home
#!/bin/sh
echo /tmp/scripthome
EOF
    chmod a+rx \
        "$TESTS_WORKDIR"/cont-users.d/scriptuser/id \
        "$TESTS_WORKDIR"/cont-users.d/scriptuser/gid \
        "$TESTS_WORKDIR"/cont-users.d/scriptuser/home

    DOCKER_EXTRA_OPTS=()
    DOCKER_EXTRA_OPTS+=("-e" "USER_ID=2000")
    DOCKER_EXTRA_OPTS+=("-e" "GROUP_ID=3000")
    DOCKER_EXTRA_OPTS+=("-e" "SUP_GROUP_IDS=5100,9999")
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR"/cont-groups.d/mygrp:/etc/cont-groups.d/mygrp)
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR"/cont-groups.d/renamedgrp:/etc/cont-groups.d/renamedgrp)
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR"/cont-groups.d/disabledgrp:/etc/cont-groups.d/disabledgrp)
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR"/cont-groups.d/scriptgrp:/etc/cont-groups.d/scriptgrp)
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR"/cont-users.d/myuser:/etc/cont-users.d/myuser)
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR"/cont-users.d/renameduser:/etc/cont-users.d/renameduser)
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR"/cont-users.d/disableduser:/etc/cont-users.d/disableduser)
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR"/cont-users.d/hashuser:/etc/cont-users.d/hashuser)
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR"/cont-users.d/passuser:/etc/cont-users.d/passuser)
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR"/cont-users.d/scriptuser:/etc/cont-users.d/scriptuser)

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

@test "Checking that default users and groups are present..." {
    dump_daemon_logs

    # Get the OS.
    run exec_container_daemon sh -c "cat /etc/os-release"
    [ "$status" -eq 0 ]

    # Parse the OS.
    regex="^ID=.*"
    for item in "${lines[@]}"; do
        if [[ "$item" =~ $regex ]]; then
            OS="${item#*=}"
            break;
        fi
    done
    if [ -z "$OS" ]; then
        echo "ERROR: Could not get OS from /etc/os-release."
        exit 1
    fi

    # Check the root user/group.
    run exec_container_daemon sh -c "grep -q '^root:x:0:0::' /etc/passwd"
    echo "User 'root' /etc/passwd: $status"
    [ "$status" -eq 0 ]
    run exec_container_daemon sh -c "grep -q '^root:x:0:' /etc/group"
    echo "User 'root' /etc/group: $status"
    [ "$status" -eq 0 ]
    run exec_container_daemon sh -c "grep -q '^root:' /etc/shadow"
    echo "User 'root' /etc/shadow: $status"
    [ "$status" -eq 0 ]

    # Check the app user/group.
    run exec_container_daemon sh -c "grep -q '^app:x:2000:3000::' /etc/passwd"
    echo "User 'app' /etc/passwd: $status"
    [ "$status" -eq 0 ]
    run exec_container_daemon sh -c "grep -q '^app:x:3000:' /etc/group"
    echo "User 'app' /etc/group: $status"
    [ "$status" -eq 0 ]
    run exec_container_daemon sh -c "grep -q '^app:' /etc/shadow"
    echo "User 'app' /etc/shadow: $status"
    [ "$status" -eq 0 ]

    # Check the shadow group.
    run exec_container_daemon sh -c "grep -q '^shadow:x:42:' /etc/group"
    echo "Group 'shadow' /etc/group: $status"
    [ "$status" -eq 0 ]

    # Check the cinit group.
    run exec_container_daemon sh -c "grep -q '^cinit:x:72:' /etc/group"
    echo "Group 'cinit' /etc/group: $status"
    [ "$status" -eq 0 ]

    # Check ubuntu/debian specific users/groups/
    case "$OS" in
        debian|ubuntu)
            # Check the staff group.
            run exec_container_daemon sh -c "grep -q '^staff:x:50:' /etc/group"
            echo "Group 'staff' /etc/group: $status"
            [ "$status" -eq 0 ]

            # Check the nogroup group.
            run exec_container_daemon sh -c "grep -q '^nogroup:x:65534:' /etc/group"
            echo "Group 'nogroup' /etc/group: $status"
            [ "$status" -eq 0 ]

            # Check the '_apt' user.
            run exec_container_daemon sh -c "grep -q '^_apt:x:105:65534::' /etc/passwd"
            echo "User '_apt' /etc/passwd: $status"
            [ "$status" -eq 0 ]
            run exec_container_daemon sh -c "grep -q '^_apt:' /etc/shadow"
            echo "User '_apt' /etc/shadow: $status"
            [ "$status" -eq 0 ]
            ;;
    esac
}

@test "Checking that a group is created from cont-groups.d..." {
    dump_daemon_logs

    run exec_container_daemon sh -c "grep -q '^mygrp:x:5100:' /etc/group"
    echo "Group 'mygrp' /etc/group: $status"
    [ "$status" -eq 0 ]
}

@test "Checking that a group name can be overridden via cont-groups.d/name..." {
    dump_daemon_logs

    # Directory is renamedgrp, but the group name is othergrp.
    run exec_container_daemon sh -c "grep -q '^othergrp:x:5101:' /etc/group"
    echo "Group 'othergrp' /etc/group: $status"
    [ "$status" -eq 0 ]
    run exec_container_daemon sh -c "grep -q '^renamedgrp:' /etc/group"
    echo "Group 'renamedgrp' should not exist: $status"
    [ "$status" -ne 0 ]
}

@test "Checking that a disabled group from cont-groups.d is not created..." {
    dump_daemon_logs

    run exec_container_daemon sh -c "grep -q '^disabledgrp:' /etc/group"
    echo "Group 'disabledgrp' should not exist: $status"
    [ "$status" -ne 0 ]
}

@test "Checking that a group ID can be provided by an executable cont-groups.d/id..." {
    dump_daemon_logs

    run exec_container_daemon sh -c "grep -q '^scriptgrp:x:5103:' /etc/group"
    echo "Group 'scriptgrp' /etc/group: $status"
    [ "$status" -eq 0 ]
}

@test "Checking that a user is created from cont-users.d..." {
    dump_daemon_logs

    run exec_container_daemon sh -c "grep -q '^myuser:x:6100:5100::/tmp/myhome:/sbin/nologin$' /etc/passwd"
    echo "User 'myuser' /etc/passwd: $status"
    [ "$status" -eq 0 ]
    run exec_container_daemon sh -c "grep -q '^myuser:' /etc/shadow"
    echo "User 'myuser' /etc/shadow: $status"
    [ "$status" -eq 0 ]
}

@test "Checking that a user name can be overridden via cont-users.d/name..." {
    dump_daemon_logs

    # Directory is renameduser, but the user name is otheruser.
    run exec_container_daemon sh -c "grep -q '^otheruser:x:6101:5100::' /etc/passwd"
    echo "User 'otheruser' /etc/passwd: $status"
    [ "$status" -eq 0 ]
    run exec_container_daemon sh -c "grep -q '^renameduser:' /etc/passwd"
    echo "User 'renameduser' should not exist: $status"
    [ "$status" -ne 0 ]
}

@test "Checking that a disabled user from cont-users.d is not created..." {
    dump_daemon_logs

    run exec_container_daemon sh -c "grep -q '^disableduser:' /etc/passwd"
    echo "User 'disableduser' should not exist: $status"
    [ "$status" -ne 0 ]
    run exec_container_daemon sh -c "grep -q '^disableduser:' /etc/shadow"
    echo "User 'disableduser' should not exist in shadow: $status"
    [ "$status" -ne 0 ]
}

@test "Checking that user supplementary groups are applied from cont-users.d/grps..." {
    dump_daemon_logs

    # myuser should be listed as a member of mygrp and cinit.
    run exec_container_daemon sh -c "grep -E '^mygrp:x:5100:.*myuser' /etc/group"
    echo "myuser in mygrp: $status / $output"
    [ "$status" -eq 0 ]
    run exec_container_daemon sh -c "grep -E '^cinit:x:72:.*myuser' /etc/group"
    echo "myuser in cinit: $status / $output"
    [ "$status" -eq 0 ]
}

@test "Checking that a user password_hash is applied from cont-users.d..." {
    dump_daemon_logs

    expected="$(cat "$TESTS_WORKDIR"/expected_password_hash)"
    run exec_container_daemon sh -c 'awk -F: '\''$1=="hashuser" {print $2}'\'' /etc/shadow'
    echo "hashuser password field: $output"
    echo "expected: $expected"
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
}

@test "Checking that a user password is hashed from cont-users.d/password..." {
    dump_daemon_logs

    # Password should be hashed (not '!' and starts with '$').
    run exec_container_daemon sh -c "awk -F: '\$1==\"passuser\" {print \$2}' /etc/shadow"
    echo "passuser password field: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == \$* ]]
    [ "$output" != "!" ]
    [ "$output" != "secretpass" ]
}

@test "Checking that user attributes can be provided by executable cont-users.d files..." {
    dump_daemon_logs

    run exec_container_daemon sh -c "grep -q '^scriptuser:x:6105:5100::/tmp/scripthome:/sbin/nologin$' /etc/passwd"
    echo "User 'scriptuser' /etc/passwd: $status"
    [ "$status" -eq 0 ]
}

@test "Checking that SUP_GROUP_IDS assigns app to existing and new groups..." {
    dump_daemon_logs

    # 5100 maps to existing mygrp; 9999 creates grp9999.
    run exec_container_daemon sh -c "grep -E '^mygrp:x:5100:.*app' /etc/group"
    echo "app in mygrp: $status / $output"
    [ "$status" -eq 0 ]
    run exec_container_daemon sh -c "grep -q '^grp9999:x:9999:app$' /etc/group"
    echo "app in grp9999: $status / $output"
    [ "$status" -eq 0 ]
}

@test "Checking that service sgid always includes GROUP_ID..." {
    # Discard docker CLI stderr (platform mismatch warnings under QEMU) so it
    # does not pollute $output used for an exact comparison.
    run no_stderr docker run --rm --entrypoint /defaults/service/sgid \
        -e GROUP_ID=3000 \
        "$DOCKER_IMAGE"
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    [ "$status" -eq 0 ]
    [ "$output" = "3000" ]
}

@test "Checking that service sgid merges GROUP_ID with SUP_GROUP_IDS..." {
    # Discard docker CLI stderr (platform mismatch warnings under QEMU) so it
    # does not pollute $output used for an exact comparison.
    run no_stderr docker run --rm --entrypoint /defaults/service/sgid \
        -e GROUP_ID=3000 \
        -e SUP_GROUP_IDS=5100,9999 \
        "$DOCKER_IMAGE"
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    [ "$status" -eq 0 ]
    [ "$output" = $'3000\n5100\n9999' ]
}

@test "Checking that service sgid deduplicates GROUP_ID..." {
    # Discard docker CLI stderr (platform mismatch warnings under QEMU) so it
    # does not pollute $output used for an exact comparison.
    run no_stderr docker run --rm --entrypoint /defaults/service/sgid \
        -e GROUP_ID=3000 \
        -e SUP_GROUP_IDS=3000,5100 \
        "$DOCKER_IMAGE"
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    [ "$status" -eq 0 ]
    [ "$output" = $'3000\n5100' ]
}

@test "Checking that an invalid group ID in cont-groups.d causes a failure..." {
    mkdir -p "$TESTS_WORKDIR"/badgrp
    echo "notanumber" > "$TESTS_WORKDIR"/badgrp/id

    docker_run --rm -v "$TESTS_WORKDIR"/badgrp:/etc/cont-groups.d/badgrp "$DOCKER_IMAGE"
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    [ "$status" -eq 1 ]
    [[ "$output" == *"group id defined at /etc/cont-groups.d/badgrp is not valid."* ]]
}

@test "Checking that an invalid group name in cont-groups.d causes a failure..." {
    mkdir -p "$TESTS_WORKDIR"/badname
    echo "5200" > "$TESTS_WORKDIR"/badname/id
    echo "BadName" > "$TESTS_WORKDIR"/badname/name

    docker_run --rm -v "$TESTS_WORKDIR"/badname:/etc/cont-groups.d/badname "$DOCKER_IMAGE"
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    [ "$status" -eq 1 ]
    [[ "$output" == *"group name defined at /etc/cont-groups.d/badname is not valid."* ]]
}

@test "Checking that an invalid user name in cont-users.d causes a failure..." {
    mkdir -p "$TESTS_WORKDIR"/BadUser
    echo "6200" > "$TESTS_WORKDIR"/BadUser/id
    echo "0" > "$TESTS_WORKDIR"/BadUser/gid

    docker_run --rm -v "$TESTS_WORKDIR"/BadUser:/etc/cont-users.d/BadUser "$DOCKER_IMAGE"
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    [ "$status" -eq 1 ]
    [[ "$output" == *"user name defined at /etc/cont-users.d/BadUser is not valid."* ]]
}

@test "Checking that a user with a missing primary group causes a failure..." {
    mkdir -p "$TESTS_WORKDIR"/orphan
    echo "6201" > "$TESTS_WORKDIR"/orphan/id
    echo "99999" > "$TESTS_WORKDIR"/orphan/gid

    docker_run --rm -v "$TESTS_WORKDIR"/orphan:/etc/cont-users.d/orphan "$DOCKER_IMAGE"
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    [ "$status" -eq 1 ]
    [[ "$output" == *"group ID '99999' doesn't exist."* ]]
}

# vim:ft=sh:ts=4:sw=4:et:sts=4
