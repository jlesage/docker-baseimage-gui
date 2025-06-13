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

@test "Checking container's exit code when init script fails..." {
    echo "#!/bin/sh
    exit 200" > "$TESTS_WORKDIR"/00-test-script-failure.sh
    chmod a+rx "$TESTS_WORKDIR"/00-test-script-failure.sh

    docker_run --rm -v "$TESTS_WORKDIR"/00-test-script-failure.sh:/etc/cont-init.d/00-test-script-failure.sh $DOCKER_IMAGE
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    [ "$status" -eq 200 ]
}

@test "Checking that init script without execute permission is ignored..." {
    echo "#!/bin/sh
    exit 0" > "$TESTS_WORKDIR"/startapp.sh
    chmod a+rx "$TESTS_WORKDIR"/startapp.sh

    echo "#!/bin/sh
    exit 200" > "$TESTS_WORKDIR"/00-test-script-failure.sh

    docker_run --rm -v "$TESTS_WORKDIR"/startapp.sh:/startapp.sh -v "$TESTS_WORKDIR"/00-test-script-failure.sh:/etc/cont-init.d/00-test-script-failure.sh $DOCKER_IMAGE
    regex=".* 00-test-script-failure.sh: WARNING: not executable, ignoring"
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
    echo "STATUS: $status"
    [ "$status" -eq 0 ]
    [[ "$item" =~ $regex ]]
}

# vim:ft=sh:ts=4:sw=4:et:sts=4
