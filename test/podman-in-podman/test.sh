#!/bin/bash
# The default options, as root: rootful Podman.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "podman-check" /usr/local/share/podman-check.sh

# Podman 4.9 (ubuntu:noble) has /etc/cni/net.d/87-podman-bridge.conflist. When Podman
# selects a network backend for a store with no defaultNetworkBackend file, it reads that
# file and warns on a store with no images, and it selects CNI on a store with images.
graph_root=$(podman info --format '{{.Store.GraphRoot}}')
forget_backend() { rm -f "${graph_root}/defaultNetworkBackend"; }
one_start_line() {
    forget_backend
    local out status
    out=$(/usr/local/share/podman-check.sh 2> /tmp/check.err)
    status=$?
    printf '%s\n' "$out"
    cat /tmp/check.err >&2
    local line='^podman-in-podman: rootful Podman [^[:space:]]+ for root\.$'
    [ "$status" -eq 0 ] && [ ! -s /tmp/check.err ] && [[ "$out" =~ $line ]]
}
check "one start line on a store with no backend file" one_start_line

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
check "no docker command" absent docker
check "no docker-compose" absent docker-compose
check "no podman-docker" not_installed podman-docker
check "containers.conf drop-in" test -f /etc/containers/containers.conf.d/50-podman-in-podman.conf
check "compose drop-in" test -f /etc/containers/containers.conf.d/50-podman-in-podman-compose.conf
check "no docker.sock link" test ! -L /var/run/docker.sock
check "cgroups v2" info_is '{{.Host.CgroupsVersion}}' v2
check "netavark" info_is '{{.Host.NetworkBackend}}' netavark
check "crun" info_is '{{.Host.OCIRuntime.Name}}' crun
check "cgroupfs" info_is '{{.Host.CgroupManager}}' cgroupfs
check "run hello" run_hello
check "no conmon cgroup warning" no_conmon_warning
netavark_with_images() {
    forget_backend
    info_is '{{.Host.NetworkBackend}}' netavark
}
check "netavark on a store with images and no backend file" netavark_with_images

reportResults
