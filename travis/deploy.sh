#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

echo "Pushing docker image to $DOCKER_REPO:$TAG..."
docker login -u "$DOCKER_USERNAME" -p "$DOCKER_PASSWORD" 
docker push $DOCKER_REPO:$TAG
