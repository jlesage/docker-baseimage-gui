
get_init_script_exit_code() {
    script=$1
    lines=$2
    regex_success=".* $script: terminated successfully"
    regex_failure=".* $script: terminated with error ([0-9]+)"

    for item in "${lines[@]}"; do
        if [[ "$item" =~ $regex_failure ]]; then
            echo ${BASH_REMATCH[1]}
            return 0
        elif [[ "$item" =~ $regex_success ]]; then
            echo "0"
            return 0
        fi
    done

    echo "ERROR: No exit code found for init script '$script'." >&2
    return 1
}

docker_run() {
    run docker run "$@"
}

[ -n "$DOCKER_IMAGE" ]

# Make sure the docker image exists.
docker inspect "$DOCKER_IMAGE" > /dev/null

# Create workdir to store temporary stuff.
TESTS_WORKDIR="$(mktemp -d)"

