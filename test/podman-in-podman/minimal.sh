#!/bin/bash
# buildah=false, skopeo=false and compose=none: only Podman.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

# The CLI can start the test before the entrypoint of the Feature ends.
check "entrypoint done" timeout 60 sh -c 'until [ -f /run/podman-in-podman/ready ]; do sleep 0.5; done'

absent() { ! command -v "$1"; }

check "no buildah" absent buildah
check "no skopeo" absent skopeo
check "no podman-compose" absent podman-compose
check "no docker-compose" absent docker-compose
check "run hello" podman run --rm quay.io/podman/hello

reportResults
