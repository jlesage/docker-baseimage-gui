[ -n "$DOCKER_REPO" ]
[ -n "$TRAVIS_JOB_ID" ]

DOCKER_IMAGE="$DOCKER_REPO:$TRAVIS_JOB_ID"

# Make sure the docker image exists.
docker inspect "$DOCKER_IMAGE" > /dev/null
