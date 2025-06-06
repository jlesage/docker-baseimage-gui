#!/bin/env bats

setup() {
    load setup_common

    echo "TEST_VAL" > "$TESTS_WORKDIR"/TEST_VAR_STATIC
    echo "USER_VAL" > "$TESTS_WORKDIR"/TEST_VAR_STATIC_OVERRIDE

    echo "#!/bin/sh
    echo TEST_VAL" > "$TESTS_WORKDIR"/TEST_VAR_SUCCESS
    chmod a+rx "$TESTS_WORKDIR"/TEST_VAR_SUCCESS

    echo "#!/bin/sh
    echo TEST_VAL
    exit 100" > "$TESTS_WORKDIR"/TEST_VAR_UNSET
    chmod a+rx "$TESTS_WORKDIR"/TEST_VAR_UNSET

    echo "#!/bin/sh
    echo TEST_VAL" > "$TESTS_WORKDIR"/TEST_VAR_OVERRIDE
    chmod a+rx "$TESTS_WORKDIR"/TEST_VAR_OVERRIDE

    DOCKER_EXTRA_OPTS=()
    DOCKER_EXTRA_OPTS+=("-e" "TEST_VAR_OVERRIDE=USER_VAL")
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR"/TEST_VAR_STATIC:/etc/cont-env.d/TEST_VAR_STATIC)
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR"/TEST_VAR_STATIC_OVERRIDE:/etc/cont-env.d/TEST_VAR_STATIC_OVERRIDE)
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR"/TEST_VAR_SUCCESS:/etc/cont-env.d/TEST_VAR_SUCCESS)
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR"/TEST_VAR_UNSET:/etc/cont-env.d/TEST_VAR_UNSET)
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR"/TEST_VAR_OVERRIDE:/etc/cont-env.d/TEST_VAR_OVERRIDE)

    load setup_container_daemon
}

teardown() {
    load teardown_container_daemon
    load teardown_common
}

@test "Checking that environment variable is loaded from static file..." {
    # Dump docker logs before proceeding to validations.
    echo "====================================================================="
    echo " DOCKER LOGS"
    echo "====================================================================="
    getlog_container_daemon
    echo "====================================================================="
    echo " END DOCKER LOGS"
    echo "====================================================================="

    run exec_container_daemon sh -c "cat /proc/1/environ | tr '\0' '\n' | grep '^TEST_VAR_STATIC=TEST_VAL$'"
    [ "$status" -eq 0 ]
}

@test "Checking that environment variable is loaded from script..." {
    # Dump docker logs before proceeding to validations.
    echo "====================================================================="
    echo " DOCKER LOGS"
    echo "====================================================================="
    getlog_container_daemon
    echo "====================================================================="
    echo " END DOCKER LOGS"
    echo "====================================================================="

    run exec_container_daemon sh -c "cat /proc/1/environ | tr '\0' '\n' | grep '^TEST_VAR_SUCCESS=TEST_VAL$'"
    [ "$status" -eq 0 ]
}

@test "Checking that environment variable is not loaded from script with exit code 100..." {
    # Dump docker logs before proceeding to validations.
    echo "====================================================================="
    echo " DOCKER LOGS"
    echo "====================================================================="
    getlog_container_daemon
    echo "====================================================================="
    echo " END DOCKER LOGS"
    echo "====================================================================="

    run exec_container_daemon sh -c "cat /proc/1/environ | tr '\0' '\n' | grep '^TEST_VAR_UNSET='"
    [ "$status" -ne 0 ]
}

@test "Checking that environment variable is not loaded from static file when overridden by user..." {
    # Dump docker logs before proceeding to validations.
    echo "====================================================================="
    echo " DOCKER LOGS"
    echo "====================================================================="
    getlog_container_daemon
    echo "====================================================================="
    echo " END DOCKER LOGS"
    echo "====================================================================="

    run exec_container_daemon sh -c "cat /proc/1/environ | tr '\0' '\n' | grep '^TEST_VAR_STATIC_OVERRIDE=USER_VAL'"
    [ "$status" -eq 0 ]
}

@test "Checking that environment variable is not loaded from script when overridden by user..." {
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

@test "Checking that environment variable script can output to container's log..." {
    echo "#!/bin/sh
    exit 0" > "$TESTS_WORKDIR"/startapp.sh
    chmod a+rx "$TESTS_WORKDIR"/startapp.sh

    echo "#!/bin/sh
    echo TEST_VAL
    echo TEST_STDERR_OUTPUT >&2" > "$TESTS_WORKDIR"/TEST_VAR_STDERR_OUTPUT
    chmod a+rx "$TESTS_WORKDIR"/TEST_VAR_STDERR_OUTPUT

    docker_run --rm -v "$TESTS_WORKDIR"/startapp.sh:/startapp.sh -v $TESTS_WORKDIR"/TEST_VAR_STDERR_OUTPUT:/etc/cont-env.d/TEST_VAR_STDERR_OUTPUT" $DOCKER_IMAGE
    regex=".* TEST_STDERR_OUTPUT"
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

@test "Checking container's exit code when environment variable script fails..." {
    echo "#!/bin/sh
    echo TEST_VAL
    exit 200" > "$TESTS_WORKDIR"/TEST_VAR_ERR
    chmod a+rx "$TESTS_WORKDIR"/TEST_VAR_ERR

    docker_run --rm -v $TESTS_WORKDIR"/TEST_VAR_ERR:/etc/cont-env.d/TEST_VAR_ERR" $DOCKER_IMAGE
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


@test "Checking that environment variable file name is validated..." {
    echo "TEST_VAL" > "$TESTS_WORKDIR"/TEST_VAR

    docker_run --rm -v $TESTS_WORKDIR"/TEST_VAR:/etc/cont-env.d/0_TEST_INVALID_VAR_NAME" $DOCKER_IMAGE
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    [ "$status" -eq 1 ]

    docker_run --rm -v $TESTS_WORKDIR"/TEST_VAR:/etc/cont-env.d/TEST INVALID VAR NAME" $DOCKER_IMAGE
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
