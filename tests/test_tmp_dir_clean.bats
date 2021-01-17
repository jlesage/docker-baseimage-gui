#!/bin/env bats

setup() {
    load setup_common
    load setup_container_daemon
}

teardown() {
    load teardown_container_daemon
    load teardown_common
}

@test "Checking that the /tmp directory is cleaned..." {
    exec_container_daemon sh -c "touch /tmp/test_file"

    restart_container_daemon

    exec_container_daemon sh -c "[ ! -f /tmp/test_file ]"
}

# vim:ft=sh:ts=4:sw=4:et:sts=4
