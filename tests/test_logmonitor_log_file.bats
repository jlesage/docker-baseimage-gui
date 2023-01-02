#!/bin/env bats

setup() {
    load setup_common

    # This will be used to disabled YAD.
    echo "#!/bin/sh" > "$TESTS_WORKDIR"/yad-send
    chmod +x "$TESTS_WORKDIR"/yad-send

    # Create first notification definition.
    mkdir "$TESTS_WORKDIR"/test1
    echo 'Test1 title' > "$TESTS_WORKDIR"/test1/title
    echo 'Test description' > "$TESTS_WORKDIR"/test1/desc
    echo ERROR > "$TESTS_WORKDIR"/test1/level
    cat << EOF > "$TESTS_WORKDIR"/test1/filter
#!/bin/sh
echo RUNNING_FILTER1 on: \$1
echo "\$1" | grep -q TriggerWord
EOF
    echo "/tmp/test1.log" > "$TESTS_WORKDIR"/test1/source
    chmod +x "$TESTS_WORKDIR"/test1/filter

    # Create second notification definition.
    mkdir "$TESTS_WORKDIR"/test2
    cat << EOF > "$TESTS_WORKDIR"/test2/title
#!/bin/sh
echo 'Test2 title'
EOF
    cat << EOF > "$TESTS_WORKDIR"/test2/desc
#!/bin/sh
echo 'Test description'
EOF
    cat << EOF > "$TESTS_WORKDIR"/test2/level
#!/bin/sh
echo ERROR
EOF
    cat << EOF > "$TESTS_WORKDIR"/test2/filter
#!/bin/sh
echo RUNNING_FILTER2 on: \$1
echo "\$1" | grep -q TriggerAnotherWord
EOF
    echo "log:/tmp/test1.log" > "$TESTS_WORKDIR"/test2/source
    echo "log:/tmp/test2.log" >> "$TESTS_WORKDIR"/test2/source
    chmod +x "$TESTS_WORKDIR"/test2/title
    chmod +x "$TESTS_WORKDIR"/test2/desc
    chmod +x "$TESTS_WORKDIR"/test2/level
    chmod +x "$TESTS_WORKDIR"/test2/filter

    DOCKER_EXTRA_OPTS=()
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR/yad-send:/etc/logmonitor/targets.d/yad/send")
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR/test1:/etc/logmonitor/notifications.d/test1")
    DOCKER_EXTRA_OPTS+=("-v" "$TESTS_WORKDIR/test2:/etc/logmonitor/notifications.d/test2")

    load setup_container_daemon
}

teardown() {
    load teardown_container_daemon
    load teardown_common
}

@test "Checking log monitor functionality with log files..." {
    exec_container_daemon sh -c "touch /tmp/test1.log"
    exec_container_daemon sh -c "touch /tmp/test2.log"
    sleep 20

    exec_container_daemon sh -c "echo ThisIsALine1       >> /tmp/test1.log"
    exec_container_daemon sh -c "echo TriggerWord        >> /tmp/test1.log"
    exec_container_daemon sh -c "echo ThisIsALine2       >> /tmp/test2.log"
    exec_container_daemon sh -c "echo TriggerAnotherWord >> /tmp/test2.log"
    sleep 20

    # Dump docker logs before proceeding to validations.
    echo "====================================================================="
    echo " DOCKER LOGS"
    echo "====================================================================="
    getlog_container_daemon
    echo "====================================================================="
    echo " END DOCKER LOGS"
    echo "====================================================================="

    run getlog_container_daemon
    count1=0
    count2=0
    for item in "${lines[@]}"; do
        regex1=".*ERROR: Test1 title Test description"
        regex2=".*ERROR: Test2 title Test description"
        if [[ "$item" =~ $regex1 ]]; then
            count1="$(expr $count1 + 1)"
        elif [[ "$item" =~ $regex2 ]]; then
            count2="$(expr $count2 + 1)"
        fi
    done
    [ "$count1" -eq 1 ]
    [ "$count2" -eq 1 ]
}

# vim:ft=sh:ts=4:sw=4:et:sts=4
