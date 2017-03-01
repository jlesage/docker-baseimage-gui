[ -n "$CONTAINER_ID" ]

echo "Stopping docker container..."
docker stop "$CONTAINER_ID"

echo "Removing docker container..."
docker rm "$CONTAINER_ID"

# Clear the container ID.
CONTAINER_ID=
