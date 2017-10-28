#!/bin/env bats

setup() {
    load setup_common
}

@test "Checking that all init scripts terminate successfully..." {
    run docker run --rm -p 5900:5900 -p 5800:5800 $DOCKER_IMAGE
    for item in "${lines[@]}"; do
        if [ "$item" == "[cont-init.d] done." ]; then
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
    [ "$item" == "[cont-init.d] done." ]
}
