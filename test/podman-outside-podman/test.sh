#!/bin/bash
# The default options and the default mount, as root. The test job of test-pr.yaml starts a
# rootful Podman API service on the runner in /run/user/1000/podman, the default source.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "podman-check" /usr/local/share/podman-check.sh

absent() { ! command -v "$1"; }
not_installed() { ! dpkg -s "$1" > /dev/null 2>&1; }
not_set() { [ -z "${!1+set}" ]; }
no_docker_sock() { [ ! -e /var/run/docker.sock ] && [ ! -L /var/run/docker.sock ]; }
podman_is_remote_link() {
    [ "$(command -v podman)" = /usr/local/bin/podman ] &&
        [ "$(readlink -f /usr/local/bin/podman)" = /usr/bin/podman-remote ]
}
service_is_remote() { [ "$(podman info --format '{{.Host.ServiceIsRemote}}')" = true ]; }
provider_is_podman_compose() { podman compose version | grep 'podman-compose'; }
link_to_host_socket() { [ "$(readlink /run/podman/podman.sock)" = /run/podman-host/podman.sock ]; }
one_start_line() {
    local out status
    out=$(/usr/local/share/podman-check.sh 2> /tmp/check.err)
    status=$?
    printf '%s\n' "$out"
    cat /tmp/check.err >&2
    local line='^podman-outside-podman: (rootful|rootless) Podman [^[:space:]]+ on the host for root\.$'
    [ "$status" -eq 0 ] && [ ! -s /tmp/check.err ] && [[ "$out" =~ $line ]]
}
# The check must fail with the fix on the host when the client socket does not answer.
check_fails_without_socket() {
    local out status=0
    out=$(CONTAINER_HOST=unix:///run/missing.sock /usr/local/share/podman-check.sh 2>&1) || status=$?
    printf '%s\n' "$out"
    [ "$status" -eq 1 ] &&
        grep -q '^(!) podman-outside-podman: ' <<< "$out" &&
        grep -q 'systemctl --user enable --now podman.socket' <<< "$out"
}

check "one start line" one_start_line
check "check fails without socket" check_fails_without_socket
check "ready file" test -f /run/podman-outside-podman/ready
check "podman-remote" podman-remote --version
check "socat" socat -V
check "podman-compose" podman-compose --version
check "podman is the podman-remote link" podman_is_remote_link
check "no docker command" absent docker
check "no docker-compose" absent docker-compose
check "no podman-docker" not_installed podman-docker
check "no docker.sock" no_docker_sock
check "CONTAINER_HOST" test "${CONTAINER_HOST}" = unix:///run/podman/podman.sock
check "no DOCKER_HOST" not_set DOCKER_HOST
check "no DOCKER_BUILDKIT" not_set DOCKER_BUILDKIT
check "host socket directory is a mount" mountpoint -q /run/podman-host
check "root uses the host socket through a link" link_to_host_socket
check "client of the host engine" service_is_remote
check "compose drop-in" test -f /etc/containers/containers.conf.d/50-podman-outside-podman-compose.conf
check "podman compose runs podman-compose" provider_is_podman_compose
check "run hello" podman run --rm quay.io/podman/hello

reportResults
