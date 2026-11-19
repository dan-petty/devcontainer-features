#!/bin/bash
# The rootless socket of a host user with a different uid as vscode: the entrypoint starts
# the socat proxy, and the check names rootless Podman.
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
foreign_owner() { [ "$(sudo stat -c %u /run/podman-host/podman.sock)" != "$(id -u)" ]; }
socket_mode() { [ "$(stat -c '%F %U:%G %a' /run/podman/podman.sock)" = "socket root:docker 660" ]; }
host_is_rootless() { [ "$(podman info --format '{{.Host.Security.Rootless}}')" = true ]; }
check_names_rootless() { /usr/local/share/podman-check.sh | grep '^podman-outside-podman: rootless Podman .* on the host for vscode\.$'; }

check "host socket has a different owner" foreign_owner
check "vscode cannot use the host socket" test ! -w /run/podman-host/podman.sock
check "proxy runs" proxy_runs
check "socket is root:docker 660" socket_mode
check "host engine is rootless" host_is_rootless
check "podman-check names rootless" check_names_rootless
check "run hello" podman run --rm quay.io/podman/hello

reportResults
