#!/bin/bash
# A named volume of the host engine: two containers share its data by name. A bind mount
# path resolves on the host, but a volume name needs no host path.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "podman-check" /usr/local/share/podman-check.sh

volume=popp-named-volume
podman volume rm -f "$volume" > /dev/null 2>&1 || true

read_back() { [ "$(podman run --rm -v "$volume:/d" quay.io/libpod/alpine:latest cat /d/file)" = shared ]; }
# The data of the volume is on the host, not in the dev container.
on_the_host() {
    local path
    path=$(podman volume inspect "$volume" --format '{{.Mountpoint}}') || return 1
    echo "$path"
    [ -n "$path" ] && [ ! -e "$path" ]
}
volume_gone() { ! podman volume exists "$volume"; }

check "create a volume" podman volume create "$volume"
check "write through one container" podman run --rm -v "$volume:/d" quay.io/libpod/alpine:latest sh -c 'echo shared > /d/file'
check "read through another container" read_back
check "volume data is on the host" on_the_host
podman volume rm -f "$volume" > /dev/null || echo "podman volume rm failed"
check "volume removed" volume_gone

reportResults
