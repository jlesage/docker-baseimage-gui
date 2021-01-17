[ -n "$CONTAINER_DAEMON_NAME" ]

echo "Stopping docker container..."
docker stop "$CONTAINER_DAEMON_NAME"

echo "Removing docker container..."
docker rm "$CONTAINER_DAEMON_NAME"

# Clear the container ID.
CONTAINER_DAEMON_NAME=
