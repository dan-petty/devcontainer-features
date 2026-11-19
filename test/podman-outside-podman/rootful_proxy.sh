#!/bin/bash
# The rootful socket of the host (root:root 0660) as vscode: the entrypoint starts the
# socat proxy, and the client socket is root:docker 660.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "podman-check" /usr/local/share/podman-check.sh

pid_file=/run/podman-outside-podman/socat.pid
proxy_runs() {
    local cmdline
    cmdline=$(tr '\0' ' ' 2> /dev/null < "/proc/$(cat "$pid_file" 2> /dev/null)/cmdline") || return 1
    [[ "$cmdline" == "socat "* ]]
}
in_group_docker() { id -nG | grep -qw docker; }
socket_mode() { [ "$(stat -c '%F %U:%G %a' /run/podman/podman.sock)" = "socket root:docker 660" ]; }
host_is_rootful() { [ "$(podman info --format '{{.Host.Security.Rootless}}')" = false ]; }
check_names_rootful() { /usr/local/share/podman-check.sh | grep '^podman-outside-podman: rootful Podman .* on the host for vscode\.$'; }

check "vscode cannot use the host socket" test ! -w /run/podman-host/podman.sock
check "proxy runs" proxy_runs
check "vscode is in the group docker" in_group_docker
check "socket is root:docker 660" socket_mode
check "host engine is rootful" host_is_rootful
check "podman-check names rootful" check_names_rootful
check "run hello" podman run --rm quay.io/podman/hello

reportResults
