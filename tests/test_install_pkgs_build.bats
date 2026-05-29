#!/bin/env bats

setup() {
    load setup_common
}

teardown() {
    load teardown_common
}

@test "Checking that package can be installed successfully when building container..." {
    docker_run --rm $DOCKER_IMAGE cat /etc/os-release
    [ "$status" -eq 0 ]

    regex="^ID=.*"
    for item in "${lines[@]}"; do
        if [[ "$item" =~ $regex ]]; then
            OS="${item#*=}"
            break;
        fi
    done

    case "$OS" in
        debian)
            INSTALL_PACKAGES="xterm systemd xrdp pulseaudio"
            ;;
        ubuntu)
            INSTALL_PACKAGES="xterm systemd xrdp pulseaudio"
            ;;
        *)
            INSTALL_PACKAGES="xterm"
            ;;
    esac

    echo "FROM $DOCKER_IMAGE
RUN add-pkg $INSTALL_PACKAGES
" > "$TESTS_WORKDIR"/Dockerfile.test

    docker buildx build --progress plain -o type=tar,dest=/dev/null -f "$TESTS_WORKDIR"/Dockerfile.test .
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
