#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

echo "Generating Dockerfile from template $DOCKERFILE..."
sed "s/\${BASEIMAGE}/${BASEIMAGE//\//\\/}/g" $DOCKERFILE > Dockerfile

echo "Validating Dockerfile..."
docker run -it --rm -v "$(pwd)/Dockerfile:/Dockerfile:ro" redcoolbeans/dockerlint
