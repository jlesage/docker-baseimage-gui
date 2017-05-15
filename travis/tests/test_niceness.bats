#!/bin/env bats

setup() {
    load setup_common
}

@test "Checking that a positive niceness value can be set successfully..." {
    run docker run --rm -p 5900:5900 -p 5800:5800 -e "APP_NICENESS=19" -e "FORCE_GUIAPP_EXIT_CODE=0" $DOCKER_IMAGE
    script_rc="$(get_init_script_exit_code '00-app-niceness.sh' $lines)"
    [ "$status" -eq 0 ]
    [ "$script_rc" -eq 0 ]
}

@test "Checking that a negative niceness value fails without the --cap-add=SYS_NICE option..." {
    run docker run --rm -p 5900:5900 -p 5800:5800 -e "APP_NICENESS=-1" -e "FORCE_GUIAPP_EXIT_CODE=0" $DOCKER_IMAGE
    script_rc="$(get_init_script_exit_code '00-app-niceness.sh' $lines)"
    [ "$status" -eq 0 ]
    [ "$script_rc" -eq 6 ]
}

@test "Checking that a negative niceness value succeed with the --cap-add=SYS_NICE option..." {
    run docker run --rm -p 5900:5900 -p 5800:5800 -e "APP_NICENESS=-1" -e "FORCE_GUIAPP_EXIT_CODE=0" --cap-add=SYS_NICE $DOCKER_IMAGE
    script_rc="$(get_init_script_exit_code '00-app-niceness.sh' $lines)"
    [ "$status" -eq 0 ]
    [ "$script_rc" -eq 0 ]
}
