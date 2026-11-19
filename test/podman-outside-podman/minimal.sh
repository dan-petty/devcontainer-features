#!/bin/bash
# compose=none: only the client and socat.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "podman-check" /usr/local/share/podman-check.sh

absent() { ! command -v "$1"; }

check "podman-remote" podman-remote --version
check "socat" socat -V
check "no podman-compose" absent podman-compose
check "no docker" absent docker
check "no docker-compose" absent docker-compose
check "no compose drop-in" test ! -e /etc/containers/containers.conf.d/50-podman-outside-podman-compose.conf
check "run hello" podman run --rm quay.io/podman/hello

reportResults
