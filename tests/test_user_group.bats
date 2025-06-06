#!/bin/env bats

setup() {
    load setup_common

    DOCKER_EXTRA_OPTS=()
    DOCKER_EXTRA_OPTS+=("-e" "USER_ID=2000")
    DOCKER_EXTRA_OPTS+=("-e" "GROUP_ID=3000")

    load setup_container_daemon
}

teardown() {
    load teardown_container_daemon
    load teardown_common
}

@test "Checking that default users and groups are present..." {
    # Dump docker logs before proceeding to validations.
    echo "====================================================================="
    echo " DOCKER LOGS"
    echo "====================================================================="
    getlog_container_daemon
    echo "====================================================================="
    echo " END DOCKER LOGS"
    echo "====================================================================="

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
    run exec_container_daemon sh -c "grep -q '^root::0:0::' /etc/passwd"
    echo "User 'root' /etc/passwd: $status"
    [ "$status" -eq 0 ]
    run exec_container_daemon sh -c "grep -q '^root:x:0:' /etc/group"
    echo "User 'root' /etc/group: $status"
    [ "$status" -eq 0 ]
    run exec_container_daemon sh -c "grep -q '^root:' /etc/shadow"
    echo "User 'root' /etc/shadow: $status"
    [ "$status" -eq 0 ]

    # Check the app user/group.
    run exec_container_daemon sh -c "grep -q '^app::2000:3000::' /etc/passwd"
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
            run exec_container_daemon sh -c "grep -q '^staff:x:52:' /etc/group"
            echo "Group 'staff' /etc/group: $status"
            [ "$status" -eq 0 ]

            # Check the nogroup group.
            run exec_container_daemon sh -c "grep -q '^nogroup:x:65534:' /etc/group"
            echo "Group 'nogroup' /etc/group: $status"
            [ "$status" -eq 0 ]

            # Check the '_apt' user.
            run exec_container_daemon sh -c "grep -q '^_apt::105:65534::' /etc/passwd"
            echo "User '_apt' /etc/passwd: $status"
            [ "$status" -eq 0 ]
            run exec_container_daemon sh -c "grep -q '^_apt:' /etc/shadow"
            echo "User '_apt' /etc/shadow: $status"
            [ "$status" -eq 0 ]
            ;;
    esac
}

# vim:ft=sh:ts=4:sw=4:et:sts=4
