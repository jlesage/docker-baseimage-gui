#!/bin/env bats

setup() {
    load setup_common

    echo "#!/bin/sh
    exit 50" > "$TESTS_WORKDIR"/startapp.sh
    chmod a+rx "$TESTS_WORKDIR"/startapp.sh
}

teardown() {
    load teardown_common
}

@test "Checking container's exit code when finish script terminates successfully..." {
    echo "#!/bin/sh
    exit 0" > "$TESTS_WORKDIR"/00-test-script.sh
    chmod a+rx "$TESTS_WORKDIR"/00-test-script.sh

    docker_run --rm -v "$TESTS_WORKDIR"/startapp.sh:/startapp.sh -v "$TESTS_WORKDIR"/00-test-script.sh:/etc/cont-finish.d/00-test-script.sh $DOCKER_IMAGE
    regex=".* 00-test-script.sh: terminated successfully"
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
    [ "$status" -eq 50 ]
    [[ "$item" =~ $regex ]]
}

@test "Checking container's exit code when finish script fails..." {
    echo "#!/bin/sh
    exit 200" > "$TESTS_WORKDIR"/00-test-script.sh
    chmod a+rx "$TESTS_WORKDIR"/00-test-script.sh

    docker_run --rm -v "$TESTS_WORKDIR"/startapp.sh:/startapp.sh -v "$TESTS_WORKDIR"/00-test-script.sh:/etc/cont-finish.d/00-test-script.sh $DOCKER_IMAGE
    regex=".* 00-test-script.sh: terminated with error 200"
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
    [ "$status" -eq 50 ]
    [[ "$item" =~ $regex ]]
}

@test "Checking that finish script without execute permission is ignored..." {
    echo "#!/bin/sh
    exit 200" > "$TESTS_WORKDIR"/00-test-script.sh

    docker_run --rm -v "$TESTS_WORKDIR"/startapp.sh:/startapp.sh -v "$TESTS_WORKDIR"/00-test-script.sh:/etc/cont-finish.d/00-test-script.sh $DOCKER_IMAGE
    regex=".* 00-test-script.sh: WARNING: not executable, ignoring"
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
    [ "$status" -eq 50 ]
    [[ "$item" =~ $regex ]]
}

# vim:ft=sh:ts=4:sw=4:et:sts=4
