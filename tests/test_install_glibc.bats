#!/bin/env bats

setup() {
    load setup_common
    load setup_container_daemon
}

teardown() {
    load teardown_container_daemon
    load teardown_common
}

@test "Checking that glibc can be install successfully..." {
    exec_container_daemon sh -c "cat /etc/os-release" > "$TESTS_WORKDIR"/os-release

    if grep alpine "$TESTS_WORKDIR"/os-release; then
        exec_container_daemon sh -c "/opt/base/bin/install-glibc"
    fi
}

# vim:ft=sh:ts=4:sw=4:et:sts=4
