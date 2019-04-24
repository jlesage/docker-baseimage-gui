#!/bin/env bats

setup() {
    load setup_common

    echo "Starting docker container..."
    run docker run -d --name dockertest $DOCKER_IMAGE sleep 360000
    [ "$status" -eq 0 ]
    CONTAINER_ID="$output"

    docker exec "$CONTAINER_ID" add-pkg at procps
    docker exec "$CONTAINER_ID" atd

    docker exec "$CONTAINER_ID" mkdir -p /var/run/s6/container_environment
    docker exec "$CONTAINER_ID" sh -c "echo -n ':0' > /var/run/s6/container_environment/DISPLAY"
    docker exec "$CONTAINER_ID" sh -c "echo -n 1024 > /var/run/s6/container_environment/DISPLAY_WIDTH"
    docker exec "$CONTAINER_ID" sh -c "echo -n 768 > /var/run/s6/container_environment/DISPLAY_HEIGHT"
    docker exec "$CONTAINER_ID" sh -c "sed-patch 's|/bin/s6-notifyoncheck -d||' /etc/services.d/xvfb/run"
}

teardown() {
    [ -n "$CONTAINER_ID" ]

    echo "Stopping docker container..."
    docker stop "$CONTAINER_ID"

    echo "Removing docker container..."
    docker rm "$CONTAINER_ID"

    # Clear the container ID.
    CONTAINER_ID=
}

docker_exec() {
    eval docker exec "$CONTAINER_ID" sh -c \"$*\"
}

@test "Checking that the X server can successfully starts if another instance is already running..." {
    [ -n "$CONTAINER_ID" ]

    # Start a first instance.
    docker_exec "echo /etc/services.d/xvfb/run | at now"
    sleep 1
    docker_exec cp /tmp/.X0-lock /tmp/.X0-lock.orig

    # Make sure that in a normal scenario, a second instance won't start.
    run docker_exec /usr/bin/Xvfb :0
    [ "$status" -ne 0 ]

    # Start a second instance.
    docker_exec "echo /etc/services.d/xvfb/run | at now"
    sleep 5

    # Make sure /tmp/.X0-lock changed.
    run docker_exec diff /tmp/.X0-lock /tmp/.X0-lock.orig
    [ "$status" -eq 1 ]

    # Make sure the X server runs.
    docker_exec "ps -A -o pid,args | grep -vw grep | grep -w '/usr/bin/Xvfb'"
}

@test "Checking that the X server can successfully starts if its lock file already exists..." {
    [ -n "$CONTAINER_ID" ]

    docker_exec "echo 1 > /tmp/.X0-lock"

    # Start an instance of the X server.
    docker_exec "echo /etc/services.d/xvfb/run | at now"
    sleep 1

    # Make sure the X server runs.
    run docker_exec "cat /tmp/.X0-lock"
    [ "$output" != "1" ]
    docker_exec "ps -A -o pid,args | grep -vw grep | grep -w '/usr/bin/Xvfb'"
}
