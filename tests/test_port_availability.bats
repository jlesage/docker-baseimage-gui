#!/bin/env bats

BATS_NO_PARALLELIZE_WITHIN_FILE=true

DOCKER_EXTRA_OPTS=("-p" "5901:5900" "-p" "5801:5800")

setup() {
    load setup_common
    load setup_container_daemon
}

teardown() {
    load teardown_container_daemon
}

@test "Checking availability of HTTP port 5800..." {
    TIMEOUT=15
    while (( TIMEOUT > 0 )); do
        run curl --silent --connect-timeout 2 http://127.0.0.1:5801
        [ "$status" -eq 0 ] && break
        sleep 1
        (( TIMEOUT-- ))
    done
    (( TIMEOUT > 0 ))
}

@test "Checking availability of VNC port 5900..." {
    TIMEOUT=15
    while (( TIMEOUT > 0 )); do 
        run nc -w1 -n 127.0.0.1 5901
        [ "$status" -eq 0 ] && [ "$output" == "RFB 003.008" ] && break
        sleep 1
        (( TIMEOUT-- ))
    done
    (( TIMEOUT > 0 ))
}

# vim:ft=sh:ts=4:sw=4:et:sts=4
