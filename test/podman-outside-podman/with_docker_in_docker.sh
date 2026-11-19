#!/bin/bash
# docker-in-docker and this Feature with dockerCompat in one container. dockerCompat is
# skipped, because docker-in-docker has /usr/local/share/docker-init.sh. The scenario job
# of test-pr.yaml finds the skip line in the build log. docker reaches the dockerd in the
# container, and podman reaches the host engine.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "podman-check" /usr/local/share/podman-check.sh

not_installed() { ! dpkg -s "$1" > /dev/null 2>&1; }
server_is_dockerd() {
    local out
    out=$(docker version) || return 1
    echo "$out"
    ! grep -q 'Podman Engine' <<< "$out"
}
podman_is_remote() { [ "$(podman info --format '{{.Host.ServiceIsRemote}}')" = true ]; }

check "no podman-docker" not_installed podman-docker
check "docker.sock is not a link" test ! -L /var/run/docker.sock
check "DOCKER_BUILDKIT of docker-in-docker" test "${DOCKER_BUILDKIT}" = 1
check "docker reaches dockerd" server_is_dockerd
check "dockerd works" docker run --rm quay.io/podman/hello
check "podman reaches the host engine" podman_is_remote
check "host engine works" podman run --rm quay.io/podman/hello

reportResults
