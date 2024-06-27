#!/bin/env bats

setup() {
    load setup_common

    echo "#!/bin/sh
    exit 0" > "$TESTS_WORKDIR"/startapp.sh
    chmod a+rx "$TESTS_WORKDIR"/startapp.sh

    echo "#!/bin/sh
    echo TEST_VAL" > "$TESTS_WORKDIR"/TEST_VAR_SUCCESS
    chmod a+rx "$TESTS_WORKDIR"/TEST_VAR_SUCCESS

    echo "#!/bin/sh
    exit 100" > "$TESTS_WORKDIR"/TEST_VAR_UNSET
    chmod a+rx "$TESTS_WORKDIR"/TEST_VAR_UNSET

    echo "#!/bin/sh
    exit 50" > "$TESTS_WORKDIR"/TEST_VAR_FAIL
    chmod a+rx "$TESTS_WORKDIR"/TEST_VAR_FAIL
}

teardown() {
    load teardown_common
}

@test "Checking environment variable script execution with exit code 0..." {
    docker_run --rm -v "$TESTS_WORKDIR"/startapp.sh:/startapp.sh -v "$TESTS_WORKDIR"/TEST_VAR_SUCCESS:/etc/cont-env.d/TEST_VAR_SUCCESS $DOCKER_IMAGE
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    [ "$status" -eq 0 ]
}

@test "Checking environment variable script execution with exit code 100..." {
    docker_run --rm -v "$TESTS_WORKDIR"/startapp.sh:/startapp.sh -v "$TESTS_WORKDIR"/TEST_VAR_UNSET:/etc/cont-env.d/TEST_VAR_UNSET $DOCKER_IMAGE
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    [ "$status" -eq 0 ]
}

@test "Checking environment variable script execution with exit code 50..." {
    docker_run --rm -v "$TESTS_WORKDIR"/startapp.sh:/startapp.sh -v "$TESTS_WORKDIR"/TEST_VAR_FAIL:/etc/cont-env.d/TEST_VAR_FAIL $DOCKER_IMAGE
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    [ "$status" -ne 0 ]
}

# vim:ft=sh:ts=4:sw=4:et:sts=4
