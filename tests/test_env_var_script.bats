#!/bin/env bats

setup() {
    load setup_common

    echo "#!/bin/sh
    echo TEST_VAL" > "$TESTS_WORKDIR"/TEST_VAR_SUCCESS
    chmod a+rx "$TESTS_WORKDIR"/TEST_VAR_SUCCESS

    echo "#!/bin/sh
    echo TEST_VAL
    exit 100" > "$TESTS_WORKDIR"/TEST_VAR_UNSET
    chmod a+rx "$TESTS_WORKDIR"/TEST_VAR_UNSET

    DOCKER_EXTRA_OPTS=()
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR"/TEST_VAR_SUCCESS:/etc/cont-env.d/TEST_VAR_SUCCESS)
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR"/TEST_VAR_UNSET:/etc/cont-env.d/TEST_VAR_UNSET)

    load setup_container_daemon
}

teardown() {
    load teardown_container_daemon
    load teardown_common
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

@test "Checking that environment variable is not loaded from script..." {
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

# vim:ft=sh:ts=4:sw=4:et:sts=4
