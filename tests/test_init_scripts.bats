#!/bin/env bats

setup() {
    load setup_common
}

teardown() {
    load teardown_common
}

@test "Checking that all init scripts terminate successfully..." {
    docker_run --rm $DOCKER_IMAGE
    regex=".* all container initialization scripts executed."
    for item in "${lines[@]}"; do
        if [[ "$item" =~ $regex ]]; then
            break;
        fi
    done
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    [[ "$item" =~ $regex ]]
}

# vim:ft=sh:ts=4:sw=4:et:sts=4
