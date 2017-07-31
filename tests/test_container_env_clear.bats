#!/bin/env bats

DOCKER_EXTRA_OPTS="-p 5900:5900 -p 5800:5800"

setup() {
    load setup_common
    load setup_container_daemon
}

teardown() {
    load teardown_container_daemon
}

@test "Checking that the container's environment is properly cleared after a restart..." {
    [ -n "$CONTAINER_ID" ]

    docker exec "$CONTAINER_ID" sh -c "echo 1 > /var/run/s6/container_environment/TEST_VAR"

    docker restart "$CONTAINER_ID"
    sleep 5

    docker exec "$CONTAINER_ID" sh -c "[ ! -f /var/run/s6/container_environment/TEST_VAR ]"
}
