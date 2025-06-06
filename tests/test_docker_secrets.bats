#!/bin/env bats

setup() {
    load setup_common

    echo "TEST_VAL" > "$TESTS_WORKDIR"/TEST_VAR
    echo "USER_VAL" > "$TESTS_WORKDIR"/TEST_VAR_OVERRIDE

    DOCKER_EXTRA_OPTS=()
    DOCKER_EXTRA_OPTS+=("-e" "TEST_VAR_OVERRIDE=USER_VAL")
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR"/TEST_VAR:/run/secrets/CONT_ENV_TEST_VAR)
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR"/TEST_VAR_OVERRIDE:/run/secrets/CONT_ENV_TEST_VAR_OVERRIDE)

    load setup_container_daemon
}

teardown() {
    load teardown_container_daemon
    load teardown_common
}

@test "Checking that environment variable is loaded from docker secrets..." {
    # Dump docker logs before proceeding to validations.
    echo "====================================================================="
    echo " DOCKER LOGS"
    echo "====================================================================="
    getlog_container_daemon
    echo "====================================================================="
    echo " END DOCKER LOGS"
    echo "====================================================================="

    run exec_container_daemon sh -c "cat /proc/1/environ | tr '\0' '\n' | grep '^TEST_VAR=TEST_VAL$'"
    [ "$status" -eq 0 ]
}

@test "Checking that environment variable is not loaded from docker secrets when overridden by user..." {
    # Dump docker logs before proceeding to validations.
    echo "====================================================================="
    echo " DOCKER LOGS"
    echo "====================================================================="
    getlog_container_daemon
    echo "====================================================================="
    echo " END DOCKER LOGS"
    echo "====================================================================="

    run exec_container_daemon sh -c "cat /proc/1/environ | tr '\0' '\n' | grep '^TEST_VAR_OVERRIDE=USER_VAL'"
    [ "$status" -eq 0 ]
}

@test "Checking that environment variable with unexpected file name is ignored..." {
    echo "#!/bin/sh
    exit 0" > "$TESTS_WORKDIR"/startapp.sh
    chmod a+rx "$TESTS_WORKDIR"/startapp.sh

    docker_run --rm -v "$TESTS_WORKDIR"/startapp.sh:/startapp.sh -v $TESTS_WORKDIR"/TEST_VAR:/run/secrets/TEST INVALID VAR NAME" $DOCKER_IMAGE
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

@test "Checking that environment variable file name from docker secrets is validated..." {
    docker_run --rm -v $TESTS_WORKDIR"/TEST_VAR:/run/secrets/CONT_ENV_0_TEST_INVALID_VAR_NAME" $DOCKER_IMAGE
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    [ "$status" -eq 1 ]

    docker_run --rm -v $TESTS_WORKDIR"/TEST_VAR:/run/secrets/CONT_ENV_TEST INVALID VAR NAME" $DOCKER_IMAGE
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    [ "$status" -eq 1 ]
}

# vim:ft=sh:ts=4:sw=4:et:sts=4
