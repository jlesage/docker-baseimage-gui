#!/bin/env bats

setup() {
    load setup_common
    load setup_container_daemon
}

teardown() {
    load teardown_container_daemon
    load teardown_common
}

@test "Checking that Openbox uses the shipped fontconfig cache..." {
    # Openbox reaches --startup only after loading its fonts. Fontconfig
    # rewrites a cache it does not accept, so an unchanged shipped file means
    # that load used the cache.
    run exec_container_daemon sh -c '
        set -e
        [ -f /var/run/openbox/openbox.ready ]

        seed=/opt/base/share/fontconfig/cache
        runtime=/config/xdg/cache/fontconfig
        found=0
        for cache in "$seed"/*.cache-*; do
            [ -f "$cache" ]
            name=${cache##*/}
            [ "$(md5sum "$cache" | cut -d " " -f 1)" = "$(md5sum "$runtime/$name" | cut -d " " -f 1)" ]
            [ "$(stat -c %y "$cache")" = "$(stat -c %y "$runtime/$name")" ]
            found=1
        done
        [ "$found" -eq 1 ]
    '
    echo "$output"
    [ "$status" -eq 0 ]
}

# vim:ft=sh:ts=4:sw=4:et:sts=4
