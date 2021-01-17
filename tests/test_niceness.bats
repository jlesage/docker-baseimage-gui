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

@test "Checking that a positive niceness value can be set successfully..." {
    docker_run --rm -e "APP_NICENESS=19" -v "$TESTS_WORKDIR"/startapp.sh:/startapp.sh $DOCKER_IMAGE
    script_rc="$(get_init_script_exit_code '10-check-app-niceness.sh' $lines)"
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    echo "SCRIPT_RC: $script_rc"
    [ "$status" -eq 0 ]
    [ "$script_rc" -eq 0 ]
}

@test "Checking that a negative niceness value fails without the --cap-add=SYS_NICE option..." {
    docker_run --rm -e "APP_NICENESS=-1" -v "$TESTS_WORKDIR"/startapp.sh:/startapp.sh $DOCKER_IMAGE
    script_rc="$(get_init_script_exit_code '10-check-app-niceness.sh' $lines)"
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    echo "SCRIPT_RC: $script_rc"
    [ "$status" -eq 6 ]
    [ "$script_rc" -eq 6 ]
}

@test "Checking that a negative niceness value succeed with the --cap-add=SYS_NICE option..." {
    docker_run --rm -e "APP_NICENESS=-1" -v "$TESTS_WORKDIR"/startapp.sh:/startapp.sh --cap-add=SYS_NICE $DOCKER_IMAGE
    script_rc="$(get_init_script_exit_code '10-check-app-niceness.sh' $lines)"
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    echo "SCRIPT_RC: $script_rc"
    [ "$status" -eq 0 ]
    [ "$script_rc" -eq 0 ]
}

# vim:ft=sh:ts=4:sw=4:et:sts=4
