#!/bin/bash
# The rootless socket of the host user, and vscode has the uid of that user, as with
# --userns=keep-id in the podman-host job: the client socket is a link to the host socket,
# and no socat proxy runs.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "podman-check" /usr/local/share/podman-check.sh

# The command line of each process. grep does not match itself: its line starts with grep.
socat_runs() {
    local cmdline
    for cmdline in /proc/[0-9]*/cmdline; do
        tr '\0' ' ' 2> /dev/null < "$cmdline"
        echo
    done | grep '^socat '
}
no_socat() { ! socat_runs; }
link_to_host_socket() { [ "$(readlink /run/podman/podman.sock)" = /run/podman-host/podman.sock ]; }
host_is_rootless() { [ "$(podman info --format '{{.Host.Security.Rootless}}')" = true ]; }
check_names_rootless() { /usr/local/share/podman-check.sh | grep '^podman-outside-podman: rootless Podman .* on the host for vscode\.$'; }

check "vscode can use the host socket" test -w /run/podman-host/podman.sock
check "no socat proxy" no_socat
check "client socket links to the host socket" link_to_host_socket
check "host engine is rootless" host_is_rootless
check "podman-check names rootless" check_names_rootless
check "run hello" podman run --rm quay.io/podman/hello

reportResults
