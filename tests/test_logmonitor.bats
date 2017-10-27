#!/bin/env bats

setup() {
    load setup_common
    load setup_container_daemon
}

teardown() {
    load teardown_container_daemon
}

@test "Checking log monitor functionality with log files..." {
    [ -n "$CONTAINER_ID" ]

    docker exec "$CONTAINER_ID" sh -c "sed-patch 's|LOG_FILES=|LOG_FILES=/tmp/test1.log,/tmp/test2.log|' /etc/logmonitor/logmonitor.conf"
    docker exec "$CONTAINER_ID" sh -c "mkdir -p /etc/logmonitor/notifications.d/test1"
    docker exec "$CONTAINER_ID" sh -c "echo 'Test1 title' > /etc/logmonitor/notifications.d/test1/title"
    docker exec "$CONTAINER_ID" sh -c "echo 'Test description' > /etc/logmonitor/notifications.d/test1/desc"
    docker exec "$CONTAINER_ID" sh -c "echo ERROR > /etc/logmonitor/notifications.d/test1/level"
    docker exec "$CONTAINER_ID" sh -c "echo '#!/bin/sh' >> /etc/logmonitor/notifications.d/test1/filter"
    docker exec "$CONTAINER_ID" sh -c "echo 'echo RUNNING_FILTER1' >> /etc/logmonitor/notifications.d/test1/filter"
    docker exec "$CONTAINER_ID" sh -c "echo 'echo \"\$1\" | grep -q TriggerWord' >> /etc/logmonitor/notifications.d/test1/filter"
    docker exec "$CONTAINER_ID" sh -c "chmod +x /etc/logmonitor/notifications.d/test1/filter"
    docker exec "$CONTAINER_ID" sh -c "cp -r /etc/logmonitor/notifications.d/test1 /etc/logmonitor/notifications.d/test2"
    docker exec "$CONTAINER_ID" sh -c "sed-patch 's/RUNNING_FILTER1/RUNNING_FILTER2/' /etc/logmonitor/notifications.d/test2/filter"
    docker exec "$CONTAINER_ID" sh -c "sed-patch 's/TriggerWord/TriggerAnotherWord/' /etc/logmonitor/notifications.d/test2/filter"
    docker exec "$CONTAINER_ID" sh -c "sed-patch 's/Test1/Test2/' /etc/logmonitor/notifications.d/test2/title"
    docker exec "$CONTAINER_ID" sh -c "rm /etc/logmonitor/targets.d/stdout/debouncing"
    docker exec "$CONTAINER_ID" sh -c "echo '#!/bin/sh' >> /etc/cont-init.d/initlogfiles.sh"
    docker exec "$CONTAINER_ID" sh -c "echo 'touch /tmp/test1.log' >> /etc/cont-init.d/initlogfiles.sh"
    docker exec "$CONTAINER_ID" sh -c "echo 'touch /tmp/test2.log' >> /etc/cont-init.d/initlogfiles.sh"
    docker exec "$CONTAINER_ID" sh -c "chmod +x /etc/cont-init.d/initlogfiles.sh"

    docker restart "$CONTAINER_ID"
    sleep 5

    docker exec "$CONTAINER_ID" sh -c "echo ThisIsALine1       >> /tmp/test1.log"
    docker exec "$CONTAINER_ID" sh -c "echo TriggerWord        >> /tmp/test1.log"
    docker exec "$CONTAINER_ID" sh -c "echo ThisIsALine2       >> /tmp/test2.log"
    docker exec "$CONTAINER_ID" sh -c "echo TriggerAnotherWord >> /tmp/test2.log"
    sleep 5

    # Dump docker logs before proceeding to validations.
    docker logs "$CONTAINER_ID"

    run docker logs "$CONTAINER_ID"
    count1=0
    count2=0
    for item in "${lines[@]}"; do
        if [ "$item" == "ERROR: Test1 title Test description" ]; then
            count1="$(expr $count1 + 1)"
        elif [ "$item" == "ERROR: Test2 title Test description" ]; then
            count2="$(expr $count2 + 1)"
        fi
    done
    [ "$count1" -eq 1 ]
    [ "$count1" -eq 1 ]
}

@test "Checking log monitor functionality with status files..." {
    [ -n "$CONTAINER_ID" ]

    docker exec "$CONTAINER_ID" sh -c "sed-patch 's|STATUS_FILES=|STATUS_FILES=/tmp/test1.status,/tmp/test2.status|' /etc/logmonitor/logmonitor.conf"
    docker exec "$CONTAINER_ID" sh -c "mkdir -p /etc/logmonitor/notifications.d/test1"
    docker exec "$CONTAINER_ID" sh -c "echo 'Test1 title' > /etc/logmonitor/notifications.d/test1/title"
    docker exec "$CONTAINER_ID" sh -c "echo 'Test description' > /etc/logmonitor/notifications.d/test1/desc"
    docker exec "$CONTAINER_ID" sh -c "echo ERROR > /etc/logmonitor/notifications.d/test1/level"
    docker exec "$CONTAINER_ID" sh -c "echo '#!/bin/sh' >> /etc/logmonitor/notifications.d/test1/filter"
    docker exec "$CONTAINER_ID" sh -c "echo 'echo \"\$1\" | grep -q TriggerWord' >> /etc/logmonitor/notifications.d/test1/filter"
    docker exec "$CONTAINER_ID" sh -c "chmod +x /etc/logmonitor/notifications.d/test1/filter"
    docker exec "$CONTAINER_ID" sh -c "cp -r /etc/logmonitor/notifications.d/test1 /etc/logmonitor/notifications.d/test2"
    docker exec "$CONTAINER_ID" sh -c "sed-patch 's/TriggerWord/TriggerAnotherWord/' /etc/logmonitor/notifications.d/test2/filter"
    docker exec "$CONTAINER_ID" sh -c "sed-patch 's/Test1/Test2/' /etc/logmonitor/notifications.d/test2/title"

    docker restart "$CONTAINER_ID"
    sleep 5

    docker exec "$CONTAINER_ID" sh -c "echo ThisIsALine1 >> /tmp/test1.log"
    docker exec "$CONTAINER_ID" sh -c "echo ThisIsALine2 >> /tmp/test2.log"
    sleep 10

    docker exec "$CONTAINER_ID" sh -c "echo TriggerWord > /tmp/test1.status"
    docker exec "$CONTAINER_ID" sh -c "echo TriggerAnotherWord > /tmp/test2.status"
    sleep 10

    # Dump docker logs before proceeding to validations.
    docker logs "$CONTAINER_ID"

    run docker logs "$CONTAINER_ID"
    count1=0
    count2=0
    for item in "${lines[@]}"; do
        if [ "$item" == "ERROR: Test1 title Test description" ]; then
            count1="$(expr $count1 + 1)"
        elif [ "$item" == "ERROR: Test2 title Test description" ]; then
            count2="$(expr $count2 + 1)"
        fi
    done
    [ "$count1" -eq 1 ]
    [ "$count2" -eq 1 ]
}
