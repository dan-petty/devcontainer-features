#!/bin/bash
# docker-in-docker and this Feature with dockerCompat in one container. dockerCompat is
# skipped, because docker-in-docker has /usr/local/share/docker-init.sh. The scenario job
# of test-pr.yaml finds the skip line in the build log. Rootful Podman on its bridge
# network has no egress here (dockerd sets the FORWARD policy to DROP), so this test does
# not check it. NOTES.md tells the users.
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

check "no podman-docker" not_installed podman-docker
check "docker.sock is not a link" test ! -L /var/run/docker.sock
check "docker reaches dockerd" server_is_dockerd
check "dockerd works" docker run --rm quay.io/podman/hello
check "rootless podman egress" podman run --rm quay.io/libpod/alpine:latest wget -q -O /dev/null https://quay.io/
check "rootful podman host network" sudo podman run --rm --network host quay.io/libpod/alpine:latest wget -q -O /dev/null https://quay.io/

reportResults
