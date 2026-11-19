#!/bin/bash
# docker-in-docker and this Feature with dockerCompat in one container. dockerCompat is
# skipped, because the Docker CLI has /usr/bin/docker. Rootful Podman on its bridge
# network has no egress here (dockerd sets the FORWARD policy to DROP), so this test does
# not check it. NOTES.md tells the users.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

# The CLI can start the test before the entrypoint of the Feature ends.
check "entrypoint done" timeout 60 sh -c 'until [ -f /run/podman-in-podman/ready ]; do sleep 0.5; done'

not_installed() { ! dpkg -s "$1" > /dev/null 2>&1; }

check "docker CLI is not podman-docker" not_installed podman-docker
check "dockerCompat skipped" grep -q '^PODMAN_DOCKER_LINK=false$' /usr/local/share/podman-in-podman/config
check "dockerd works" docker run --rm quay.io/podman/hello
check "rootless podman egress" podman run --rm quay.io/libpod/alpine:latest wget -q -O /dev/null https://quay.io/
check "rootful podman host network" sudo podman run --rm --network host quay.io/libpod/alpine:latest wget -q -O /dev/null https://quay.io/

reportResults
