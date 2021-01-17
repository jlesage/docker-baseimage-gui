
CONTAINER_DAEMON_NAME=dockertest

exec_container_daemon() {
    [ -n "$CONTAINER_DAEMON_NAME" ]
    docker exec "$CONTAINER_DAEMON_NAME" "$@"
}

getlog_container_daemon() {
    [ -n "$CONTAINER_DAEMON_NAME" ]
    docker logs "$CONTAINER_DAEMON_NAME"
}

wait_for_container_daemon() {
    echo "Waiting for the docker container daemon to be ready..."
    TIMEOUT=90
    while [ "$TIMEOUT" -ne 0 ]; do
        run exec_container_daemon sh -c "[ -f /tmp/appready ]"
        if [ "$status" -eq 0 ]; then
            break
        fi
        echo "waiting $TIMEOUT..."
        sleep 1
        TIMEOUT="$(expr "$TIMEOUT" - 1 || true)"
    done

    if [ "$TIMEOUT" -eq 0 ]; then
        echo "Docker container daemon wait timeout."
        echo "====================================================================="
        echo " DOCKER LOGS"
        echo "====================================================================="
        getlog_container_daemon
        echo "====================================================================="
        echo " END DOCKER LOGS"
        echo "====================================================================="
        false
    else
        echo "Docker container ready."
    fi
}

restart_container_daemon() {
    [ -n "$CONTAINER_DAEMON_NAME" ]

    echo "Restarting docker container daemon..."
    exec_container_daemon sh -c "rm /tmp/appready"
    docker restart "$CONTAINER_DAEMON_NAME"
    echo "Docker container daemon restarted."

    wait_for_container_daemon
}

# Make sure there is no existing instance.
docker stop "$CONTAINER_DAEMON_NAME" >/dev/null 2>&1 && docker rm "$CONTAINER_DAEMON_NAME" >/dev/null 2>&1 || true

# Create a fake startapp.h
cat << EOF > "$TESTS_WORKDIR"/startapp.sh
#!/bin/sh
touch /tmp/appready
echo "Ready!"
while true;do sleep 999; done
EOF
chmod a+rx "$TESTS_WORKDIR"/startapp.sh

# Start the container in daemon mode.
echo "Starting docker container daemon..."
docker_run -d --name "$CONTAINER_DAEMON_NAME" -v "$TESTS_WORKDIR"/startapp.sh:/startapp.sh $DOCKER_EXTRA_OPTS $DOCKER_IMAGE "${DOCKER_CMD[@]}" 2>/dev/null
echo "$output"
[ "$status" -eq 0 ]

# Wait for the container to be ready.
wait_for_container_daemon
