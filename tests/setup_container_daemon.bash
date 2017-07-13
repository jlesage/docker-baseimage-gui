# Start the container in daemon mode.
echo "Starting docker container..."
run docker run -d -p 5900:5900 -p 5800:5800 -e "KEEP_APP_RUNNING=1" --name dockertest $DOCKER_IMAGE
[ "$status" -eq 0 ]
CONTAINER_ID="$output"
