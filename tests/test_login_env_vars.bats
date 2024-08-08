#!/bin/env bats

setup() {
    load setup_common
    load setup_container_daemon
}

teardown() {
    load teardown_container_daemon
    load teardown_common
}

@test "Checking that internal environment variables are exposed when logging in..." {
    exec_container_daemon sh -c "[ -f /root/.profile ] && . /root/.profile || . /root/.docker_rc; env | grep -w XDG_DATA_HOME"
}

# vim:ft=sh:ts=4:sw=4:et:sts=4
