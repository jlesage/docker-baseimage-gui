#!/bin/env bats

setup() {
    load setup_common
    load setup_container_daemon
}

teardown() {
    load teardown_container_daemon
    load teardown_common
}

@test "Checking that package can be installed..." {
    # Dump docker logs before proceeding to validations.
    echo "====================================================================="
    echo " DOCKER LOGS"
    echo "====================================================================="
    getlog_container_daemon
    echo "====================================================================="
    echo " END DOCKER LOGS"
    echo "====================================================================="

    # Make sure packages are not already installed.
    run exec_container_daemon sh -c "command -v curl > /dev/null || false"
    [ "$status" -eq 1 ]
    run exec_container_daemon sh -c "command -v patchelf > /dev/null || false"
    [ "$status" -eq 1 ]

    # Install packages.
    run exec_container_daemon sh -c "add-pkg curl patchelf"
    echo "====================================================================="
    printf "%s\n" "${lines[@]}"
    echo "====================================================================="
    [ "$status" -eq 0 ]

    # Verify package installation.
    run exec_container_daemon sh -c "command -v curl > /dev/null || false"
    [ "$status" -eq 0 ]
    run exec_container_daemon sh -c "command -v patchelf > /dev/null || false"
    [ "$status" -eq 0 ]
}

@test "Checking that package can be removed..." {
    # Dump docker logs before proceeding to validations.
    echo "====================================================================="
    echo " DOCKER LOGS"
    echo "====================================================================="
    getlog_container_daemon
    echo "====================================================================="
    echo " END DOCKER LOGS"
    echo "====================================================================="

    # Make sure packages are not already installed.
    run exec_container_daemon sh -c "command -v curl > /dev/null || false"
    [ "$status" -eq 1 ]
    run exec_container_daemon sh -c "command -v patchelf > /dev/null || false"
    [ "$status" -eq 1 ]

    # Install packages.
    run exec_container_daemon sh -c "add-pkg curl patchelf"
    echo "====================================================================="
    printf "%s\n" "${lines[@]}"
    echo "====================================================================="
    [ "$status" -eq 0 ]

    # Verify package installation.
    run exec_container_daemon sh -c "command -v curl > /dev/null || false"
    [ "$status" -eq 0 ]
    run exec_container_daemon sh -c "command -v patchelf > /dev/null || false"
    [ "$status" -eq 0 ]

    # Remove packages.
    run exec_container_daemon sh -c "del-pkg curl patchelf"
    echo "====================================================================="
    printf "%s\n" "${lines[@]}"
    echo "====================================================================="
    [ "$status" -eq 0 ]

    # Verify packages removal.
    run exec_container_daemon sh -c "command -v curl > /dev/null || false"
    [ "$status" -eq 1 ]
    run exec_container_daemon sh -c "command -v patchelf > /dev/null || false"
    [ "$status" -eq 1 ]
}

@test "Checking that virtual package can be installed..." {
    # Dump docker logs before proceeding to validations.
    echo "====================================================================="
    echo " DOCKER LOGS"
    echo "====================================================================="
    getlog_container_daemon
    echo "====================================================================="
    echo " END DOCKER LOGS"
    echo "====================================================================="

    # Make sure packages are not already installed.
    run exec_container_daemon sh -c "command -v curl > /dev/null || false"
    [ "$status" -eq 1 ]

    # Install virtual package.
    run exec_container_daemon sh -c "add-pkg --virtual virt_pkg_test curl"
    echo "====================================================================="
    printf "%s\n" "${lines[@]}"
    echo "====================================================================="
    [ "$status" -eq 0 ]

    # Verify package installation.
    run exec_container_daemon sh -c "command -v curl > /dev/null || false"
    [ "$status" -eq 0 ]
}

@test "Checking that virtual package can be removed..." {
    # Dump docker logs before proceeding to validations.
    echo "====================================================================="
    echo " DOCKER LOGS"
    echo "====================================================================="
    getlog_container_daemon
    echo "====================================================================="
    echo " END DOCKER LOGS"
    echo "====================================================================="

    # Make sure packages are not already installed.
    run exec_container_daemon sh -c "command -v curl > /dev/null || false"
    [ "$status" -eq 1 ]

    # Install virtual package.
    run exec_container_daemon sh -c "add-pkg --virtual virt_pkg_test curl"
    echo "====================================================================="
    printf "%s\n" "${lines[@]}"
    echo "====================================================================="
    [ "$status" -eq 0 ]

    # Verify package installation.
    run exec_container_daemon sh -c "command -v curl > /dev/null || false"
    [ "$status" -eq 0 ]

    # Remove virtual package.
    run exec_container_daemon sh -c "del-pkg virt_pkg_test"
    echo "====================================================================="
    printf "%s\n" "${lines[@]}"
    echo "====================================================================="
    [ "$status" -eq 0 ]

    # Verify package removal.
    run exec_container_daemon sh -c "command -v curl > /dev/null || false"
    [ "$status" -ne 0 ]
}

# vim:ft=sh:ts=4:sw=4:et:sts=4
