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

@test "Checking that CJK fonts can be installed successfully..." {
    docker_run --rm -e "ENABLE_CJK_FONT=1" -v "$TESTS_WORKDIR"/startapp.sh:/startapp.sh $DOCKER_IMAGE
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

@test "Checking that CJK fonts can be installed successfully with a mirror..." {
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
                    MIRROR="http://in.mirror.coganng.com/ubuntu/"
                    ;;
                *)
                    MIRROR="http://in.mirror.coganng.com/ubuntu-ports/"
                    ;;
            esac
            ;;
        *)
            echo "ERROR: Unknown OS '$OS'."
            exit 1
            ;;
    esac

    docker_run --rm -e "PACKAGES_MIRROR=$MIRROR" -e "ENABLE_CJK_FONT=1" -v "$TESTS_WORKDIR"/startapp.sh:/startapp.sh $DOCKER_IMAGE
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
