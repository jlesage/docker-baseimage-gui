#!/bin/env bats

setup() {
    load setup_common
}

teardown() {
    load teardown_common
}

@test "Checking container's exit code when /startapp.sh script is missing..." {
    docker_run --rm $DOCKER_IMAGE
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
    STARTAPP_SCRIPT="$(mktemp)"
    echo '#!/bin/sh' >> "$STARTAPP_SCRIPT"
    echo 'exit 0' >> "$STARTAPP_SCRIPT"
    chmod a+rx "$STARTAPP_SCRIPT"
    docker_run --rm -v "$STARTAPP_SCRIPT":/startapp.sh $DOCKER_IMAGE
    rm "$STARTAPP_SCRIPT"
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
    STARTAPP_SCRIPT="$(mktemp)"
    echo '#!/bin/sh' >> "$STARTAPP_SCRIPT"
    echo 'exit 10' >> "$STARTAPP_SCRIPT"
    chmod a+rx "$STARTAPP_SCRIPT"
    docker_run --rm -v "$STARTAPP_SCRIPT":/startapp.sh $DOCKER_IMAGE
    rm "$STARTAPP_SCRIPT"
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

# vim:ft=sh:ts=4:sw=4:et:sts=4
