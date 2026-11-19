#!/bin/bash
# A second run of the entrypoint, with sudo and as vscode, changes nothing.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

# The CLI can start the test before the entrypoint of the Feature ends.
check "entrypoint done" timeout 60 sh -c 'until [ -f /run/podman-in-podman/ready ]; do sleep 0.5; done'

uid=$(id -u)
state() {
    cat /sys/fs/cgroup/cgroup.subtree_control /etc/subuid /etc/subgid
    stat -c '%n %a %U' /run/user "/run/user/$uid" /var/lib/containers-rootless/vscode
    cat "/run/user/$uid/podman/podman-init.pid"
    readlink /var/run/docker.sock
}
state > /tmp/state.0

check "second run with sudo" sudo /usr/local/share/podman-init.sh true
state > /tmp/state.1
check "no change after the second run" diff /tmp/state.0 /tmp/state.1
check "run as vscode" /usr/local/share/podman-init.sh true
state > /tmp/state.2
check "no change after the run as vscode" diff /tmp/state.0 /tmp/state.2
check "API service runs" kill -0 "$(cat "/run/user/$uid/podman/podman-init.pid")"
check "run hello" podman run --rm quay.io/podman/hello

reportResults
