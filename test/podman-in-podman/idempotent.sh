#!/bin/bash
# dockerCompat as vscode. A second run of the entrypoint, with sudo and as vscode, changes
# nothing. After the API service stops, a new run starts it again with a new socket.
# podman-check.sh does not accept the ready file of an earlier start.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "podman-check" /usr/local/share/podman-check.sh

uid=$(id -u)
pid_file=/run/podman-in-podman/podman-service.pid
state() {
    cat /sys/fs/cgroup/cgroup.subtree_control /etc/subuid /etc/subgid
    stat -c '%n %a %U' /run/user "/run/user/$uid" /var/lib/containers-rootless/vscode
    stat -c '%n %a %U:%G %i' /run/podman/podman.sock
    cat "$pid_file"
    readlink /var/run/docker.sock
}
service_runs() {
    local cmdline
    cmdline=$(tr '\0' ' ' < "/proc/$(cat "$pid_file")/cmdline" 2> /dev/null) || return 1
    [[ "$cmdline" == "podman system service "* ]]
}
service_stops() {
    local tries=0
    while service_runs; do
        if [ "$tries" -ge 20 ]; then
            return 1
        fi
        sleep 0.5
        tries=$((tries + 1))
    done
}
socket_mode() { [ "$(stat -c '%U:%G %a' /run/podman/podman.sock)" = "root:docker 660" ]; }
socket_is_rootful() { [ "$(podman --url unix:///var/run/docker.sock info --format '{{.Host.Security.Rootless}}')" = false ]; }

state > /tmp/state.0
check "API service runs" service_runs
check "second run with sudo" sudo /usr/local/share/podman-init.sh true
state > /tmp/state.1
check "no change after the second run" diff /tmp/state.0 /tmp/state.1
check "run as vscode" /usr/local/share/podman-init.sh true
state > /tmp/state.2
check "no change after the run as vscode" diff /tmp/state.0 /tmp/state.2
check "run hello" podman run --rm quay.io/podman/hello

# A restart: the PID file and the socket of the stopped service stay.
old_pid=$(cat "$pid_file")
check "stop the API service" sudo kill -KILL "$old_pid"
check "API service stopped" service_stops
check "old socket stays" test -S /run/podman/podman.sock
check "run after the stop" sudo /usr/local/share/podman-init.sh true
check "API service runs again" service_runs
check "new PID" test "$(cat "$pid_file")" != "$old_pid"
check "socket is root:docker 660" socket_mode
check "vscode reaches the socket" socket_is_rootful
check "podman-check after the restart" /usr/local/share/podman-check.sh

# A stop and a start of the container: the ready file of the last start stays, and it
# holds the start time of the last PID 1. podman-check.sh waits until the entrypoint
# writes the start time of the current PID 1.
ready=/run/podman-in-podman/ready
pid1_start_time() { sed 's/.*) //' /proc/1/stat | cut -d' ' -f20; }
ready_is_current() { [ "$(cat "$ready")" = "$(pid1_start_time)" ]; }
check_runs() { kill -0 "$check_pid"; }
check "ready file holds the start time of PID 1" ready_is_current
earlier_start=$(($(pid1_start_time) - 1))
check "ready file of an earlier start" sudo sh -c "echo $earlier_start > $ready"
/usr/local/share/podman-check.sh > /tmp/check.out 2>&1 &
check_pid=$!
sleep 3
check "podman-check waits for the entrypoint" check_runs
check "run the entrypoint" sudo /usr/local/share/podman-init.sh true
check "podman-check passes after the entrypoint" wait "$check_pid"
check "podman-check prints its line" grep '^podman-in-podman: rootless Podman' /tmp/check.out

reportResults
