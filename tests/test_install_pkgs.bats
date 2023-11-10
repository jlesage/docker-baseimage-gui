#!/bin/env bats

setup() {
    load setup_common

    echo "#!/bin/sh
    exit 0" > "$TESTS_WORKDIR"/startapp.sh
    chmod a+rx "$TESTS_WORKDIR"/startapp.sh
}

teardown() {
    load teardown_common
}

@test "Checking that installation of unknown package causes a failure..." {
    docker_run --rm -e "INSTALL_PACKAGES=nonexistingpackagetest" -v "$TESTS_WORKDIR"/startapp.sh:/startapp.sh $DOCKER_IMAGE
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    [ "$status" -ne 0 ]
}

@test "Checking that package can be installed successfully..." {
    docker_run --rm -e "INSTALL_PACKAGES=xterm" -v "$TESTS_WORKDIR"/startapp.sh:/startapp.sh $DOCKER_IMAGE
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

# vim:ft=sh:ts=4:sw=4:et:sts=4
