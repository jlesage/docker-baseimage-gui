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

@test "Checking that packages mirror can be set successfully..." {
    docker_run --rm -e "PACKAGES_MIRROR=https://example.com" -v "$TESTS_WORKDIR"/startapp.sh:/startapp.sh $DOCKER_IMAGE
    echo "====================================================================="
    echo " OUTPUT"
    echo "====================================================================="
    echo "$output"
    echo "====================================================================="
    echo " END OUTPUT"
    echo "====================================================================="
    echo "STATUS: $status"
    [ "$status" -eq 0 ]

    regex=".* setting packages mirror to 'https://example.com'"
    for item in "${lines[@]}"; do
        if [[ "$item" =~ $regex ]]; then
            break;
        fi
    done
    [[ "$item" =~ $regex ]]
}

@test "Checking that package can be installed successfully when a mirror is set..." {
    docker_run --rm $DOCKER_IMAGE uname -m
    [ "$status" -eq 0 ]
    ARCH="${lines[0]}"

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
        alpine)
            MIRROR="http://uk.alpinelinux.org/alpine/"
            ;;
        debian)
            MIRROR="http://ftp.us.debian.org/debian/"
            ;;
        ubuntu)
            case "$ARCH" in
                i386|i686|x86_64)
                    MIRROR="http://mirror.math.princeton.edu/pub/ubuntu/"
                    ;;
                *)
                    MIRROR="http://in.mirror.coganng.com/ubuntu-ports/"
                    ;;
            esac
            ;;
        arch)
            MIRROR="http://arch.mirror.square-r00t.net"
            ;;
        *)
            echo "ERROR: Unknown OS '$OS'."
            exit 1
            ;;
    esac

    docker_run --rm -e "PACKAGES_MIRROR=$MIRROR" -e "INSTALL_PACKAGES=patchelf" -v "$TESTS_WORKDIR"/startapp.sh:/startapp.sh $DOCKER_IMAGE
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
