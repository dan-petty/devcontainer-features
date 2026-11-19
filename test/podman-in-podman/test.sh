#!/bin/bash
# The default options, as root: rootful Podman.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

absent() { ! command -v "$1"; }
not_installed() { ! dpkg -s "$1" > /dev/null 2>&1; }
info_is() { [ "$(podman info --format "$1")" = "$2" ]; }
run_hello() {
    podman run --rm quay.io/podman/hello 2> /tmp/hello.err | grep 'Hello Podman World'
    local status=$?
    cat /tmp/hello.err >&2
    return "$status"
}
no_conmon_warning() { ! grep 'Failed to add conmon to cgroupfs sandbox cgroup' /tmp/hello.err; }

check "podman" podman --version
check "buildah" buildah --version
check "skopeo" skopeo --version
check "podman-compose" podman-compose --version
check "no docker-compose" absent docker-compose
check "no podman-docker" not_installed podman-docker
check "containers.conf drop-in" test -f /etc/containers/containers.conf.d/50-podman-in-podman.conf
check "cgroups v2" info_is '{{.Host.CgroupsVersion}}' v2
check "netavark" info_is '{{.Host.NetworkBackend}}' netavark
check "crun" info_is '{{.Host.OCIRuntime.Name}}' crun
check "cgroupfs" info_is '{{.Host.CgroupManager}}' cgroupfs
check "run hello" run_hello
check "no conmon cgroup warning" no_conmon_warning

reportResults
