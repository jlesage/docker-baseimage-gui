#!/bin/env bats

setup() {
    load setup_common
    load setup_container_daemon
}

teardown() {
    load teardown_container_daemon
    load teardown_common
}

@test "Checking log monitor functionality with log files..." {
    exec_container_daemon sh -c "sed-patch 's|LOG_FILES=|LOG_FILES=/tmp/test1.log,/tmp/test2.log|' /etc/logmonitor/logmonitor.conf"
    exec_container_daemon sh -c "mkdir -p /etc/logmonitor/notifications.d/test1"
    exec_container_daemon sh -c "echo 'Test1 title' > /etc/logmonitor/notifications.d/test1/title"
    exec_container_daemon sh -c "echo 'Test description' > /etc/logmonitor/notifications.d/test1/desc"
    exec_container_daemon sh -c "echo ERROR > /etc/logmonitor/notifications.d/test1/level"
    exec_container_daemon sh -c "echo '#!/bin/sh' >> /etc/logmonitor/notifications.d/test1/filter"
    exec_container_daemon sh -c "echo 'echo RUNNING_FILTER1' >> /etc/logmonitor/notifications.d/test1/filter"
    exec_container_daemon sh -c "echo 'echo \"\$1\" | grep -q TriggerWord' >> /etc/logmonitor/notifications.d/test1/filter"
    exec_container_daemon sh -c "chmod +x /etc/logmonitor/notifications.d/test1/filter"
    exec_container_daemon sh -c "cp -r /etc/logmonitor/notifications.d/test1 /etc/logmonitor/notifications.d/test2"
    exec_container_daemon sh -c "sed-patch 's/RUNNING_FILTER1/RUNNING_FILTER2/' /etc/logmonitor/notifications.d/test2/filter"
    exec_container_daemon sh -c "sed-patch 's/TriggerWord/TriggerAnotherWord/' /etc/logmonitor/notifications.d/test2/filter"
    exec_container_daemon sh -c "sed-patch 's/Test1/Test2/' /etc/logmonitor/notifications.d/test2/title"
    exec_container_daemon sh -c "rm /etc/logmonitor/targets.d/stdout/debouncing"
    exec_container_daemon sh -c "echo '#!/bin/sh' >> /etc/cont-init.d/initlogfiles.sh"
    exec_container_daemon sh -c "echo 'touch /tmp/test1.log' >> /etc/cont-init.d/initlogfiles.sh"
    exec_container_daemon sh -c "echo 'touch /tmp/test2.log' >> /etc/cont-init.d/initlogfiles.sh"
    exec_container_daemon sh -c "chmod +x /etc/cont-init.d/initlogfiles.sh"

    restart_container_daemon

    # Make sure the logmonitor has been started.
    sleep 10

    exec_container_daemon sh -c "echo ThisIsALine1       >> /tmp/test1.log"
    exec_container_daemon sh -c "echo TriggerWord        >> /tmp/test1.log"
    exec_container_daemon sh -c "echo ThisIsALine2       >> /tmp/test2.log"
    exec_container_daemon sh -c "echo TriggerAnotherWord >> /tmp/test2.log"
    sleep 5

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

@test "Checking log monitor functionality with status files..." {
    exec_container_daemon sh -c "sed-patch 's|STATUS_FILES=|STATUS_FILES=/tmp/test1.status,/tmp/test2.status|' /etc/logmonitor/logmonitor.conf"
    exec_container_daemon sh -c "mkdir -p /etc/logmonitor/notifications.d/test1"
    exec_container_daemon sh -c "echo 'Test1 title' > /etc/logmonitor/notifications.d/test1/title"
    exec_container_daemon sh -c "echo 'Test description' > /etc/logmonitor/notifications.d/test1/desc"
    exec_container_daemon sh -c "echo ERROR > /etc/logmonitor/notifications.d/test1/level"
    exec_container_daemon sh -c "echo '#!/bin/sh' >> /etc/logmonitor/notifications.d/test1/filter"
    exec_container_daemon sh -c "echo 'echo \"\$1\" | grep -q TriggerWord' >> /etc/logmonitor/notifications.d/test1/filter"
    exec_container_daemon sh -c "chmod +x /etc/logmonitor/notifications.d/test1/filter"
    exec_container_daemon sh -c "cp -r /etc/logmonitor/notifications.d/test1 /etc/logmonitor/notifications.d/test2"
    exec_container_daemon sh -c "sed-patch 's/TriggerWord/TriggerAnotherWord/' /etc/logmonitor/notifications.d/test2/filter"
    exec_container_daemon sh -c "sed-patch 's/Test1/Test2/' /etc/logmonitor/notifications.d/test2/title"

    restart_container_daemon

    exec_container_daemon sh -c "echo ThisIsALine1 >> /tmp/test1.log"
    exec_container_daemon sh -c "echo ThisIsALine2 >> /tmp/test2.log"
    sleep 10

    exec_container_daemon sh -c "echo TriggerWord > /tmp/test1.status"
    exec_container_daemon sh -c "echo TriggerAnotherWord > /tmp/test2.status"
    sleep 10

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
