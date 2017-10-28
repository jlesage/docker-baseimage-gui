#!/bin/env bats

setup() {
    load setup_common
}

@test "Checking container's exit code when /startapp.sh script is missing..." {
    run docker run --rm -p 5900:5900 -p 5800:5800 $DOCKER_IMAGE
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    [ "$status" -eq 5 ]
}

@test "Checking container's exit code when forcing application's termination with success..." {
    run docker run --rm -p 5900:5900 -p 5800:5800 -e "FORCE_APP_EXIT_CODE=0" $DOCKER_IMAGE
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    [ "$status" -eq 0 ]
}

@test "Checking container's exit code when forcing application's termination with custom error..." {
    run docker run --rm -p 5900:5900 -p 5800:5800 -e "FORCE_APP_EXIT_CODE=10" $DOCKER_IMAGE
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    [ "$status" -eq 10 ]
}
