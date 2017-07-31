# Start the container in daemon mode.
echo "Starting docker container..."
run docker run -d -e "KEEP_APP_RUNNING=1" $DOCKER_EXTRA_OPTS --name dockertest $DOCKER_IMAGE
[ "$status" -eq 0 ]
CONTAINER_ID="$output"
