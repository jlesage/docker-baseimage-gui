#!/bin/env bats

DOCKER_EXTRA_OPTS="-p 5900:5900 -p 5800:5800 -e SECURE_CONNECTION=1 -e USE_DEFAULT_DH_PARAMS=1"

setup() {
    load setup_common
    load setup_container_daemon
}

teardown() {
    load teardown_container_daemon
}

@test "Checking availability of HTTPs port 5800..." {
    TIMEOUT=30
    while (( TIMEOUT > 0 )); do
        run curl --silent --insecure --connect-timeout 2 https://127.0.0.1:5800
        [ "$status" -eq 0 ] && break
        sleep 1
        (( TIMEOUT-- ))
    done
    (( TIMEOUT > 0 ))
}

@test "Checking availability of VNC SSL port 5900..." {
    TIMEOUT=30
    while (( TIMEOUT > 0 )); do
        run timeout 2 ncat --ssl -n 127.0.0.1 5900
        [ "$output" == "RFB 003.008" ] && break
        sleep 1
        (( TIMEOUT-- ))
    done
    (( TIMEOUT > 0 ))
}
