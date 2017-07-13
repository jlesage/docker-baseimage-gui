
get_init_script_exit_code() {
    script=$1
    lines=$2
    regex="^\[cont-init\.d\] $script: exited ([0-9]+)\.$"

    for item in "${lines[@]}"; do
        if [[ "$item" =~ $regex ]]; then
            echo ${BASH_REMATCH[1]}
            return 0;
        fi
    done

    echo "ERROR: No exit code found for init script '$script'." >&2
    return 1
}

[ -n "$DOCKER_IMAGE" ]

# Make sure the docker image exists.
docker inspect "$DOCKER_IMAGE" > /dev/null
