#!/bin/bash
# Rootful Podman through sudo: resource limits and the default bridge network.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

limits_apply() {
    local out
    out=$(sudo podman run --rm --memory 64m --cpus 0.5 quay.io/libpod/alpine:latest cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/cpu.max)
    echo "$out"
    [ "$out" = "$(printf '67108864\n50000 100000')" ]
}
bridge_subnet_is() { [ "$(sudo podman network inspect podman --format '{{range .Subnets}}{{.Subnet}}{{end}}')" = "$1" ]; }
bridge_address() { sudo podman run --rm quay.io/libpod/alpine:latest ip -4 -o addr show eth0 | grep 'inet 10\.88\.'; }

check "memory and cpu limits" limits_apply
check "bridge subnet" bridge_subnet_is 10.88.0.0/16
check "bridge address" bridge_address
check "bridge egress" sudo podman run --rm quay.io/libpod/alpine:latest wget -q -O /dev/null https://quay.io/

reportResults
