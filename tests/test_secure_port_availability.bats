#!/bin/env bats

setup() {
    load setup_common

    if [ ! -f "$TESTS_WORKDIR"/dhparam.pem ]; then
        openssl dhparam -dsaparam -out "$TESTS_WORKDIR"/dhparam.pem 2048 > /dev/null 2>&1
    fi

    DOCKER_EXTRA_OPTS=("-p" "5900:5900" "-p" "5800:5800" "-e" "SECURE_CONNECTION=1" "-e" "USE_DEFAULT_DH_PARAMS=1" "-v" "$TESTS_WORKDIR/dhparam.pem:/config/certs/dhparam.pem:rw")
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
        run no_stderr timeout 2 openssl s_client -quiet -verify_quiet -connect 127.0.0.1:5900 2>/dev/null
        [ "$output" == "RFB 003.008" ] && break
        sleep 1
        (( TIMEOUT-- ))
    done
    (( TIMEOUT > 0 ))
}

# vim:ft=sh:ts=4:sw=4:et:sts=4
