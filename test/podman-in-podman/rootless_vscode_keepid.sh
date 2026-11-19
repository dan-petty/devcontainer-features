#!/bin/bash
# Rootless Podman as vscode. The podman-host job of test-pr.yaml also runs this scenario
# under rootless Podman with --userns=keep-id. Keep-id starts the container as the host
# user, which is not vscode on a runner, so the scenario sets containerUser to root.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "podman-check" /usr/local/share/podman-check.sh

uid=$(id -u)
info_is() { [ "$(podman info --format "$1")" = "$2" ]; }
# podman info of Podman 4.9 (ubuntu:noble) has no RootlessNetworkCmd.
default_network_is_pasta() {
    local id mode
    id=$(podman create quay.io/libpod/alpine:latest true)
    mode=$(podman inspect --format '{{.HostConfig.NetworkMode}}' "$id")
    podman rm "$id" > /dev/null
    [ "$mode" = pasta ]
}
runtime_dir_is_private() { [ "$(stat -c '%a %U' "/run/user/$uid")" = "700 vscode" ]; }
# Each subuid range of vscode must lie inside one range of the uid map.
subuid_inside_map() {
    awk -v u=vscode -v o="$uid" '
        FNR == NR { lo[NR] = $1; hi[NR] = $1 + $3 - 1; n = NR; next }
        {
            split($0, f, ":")
            if (f[1] != u && f[1] != o) next
            seen++
            ok = 0
            for (i = 1; i <= n; i++) if (f[2] >= lo[i] && f[2] + f[3] - 1 <= hi[i]) ok = 1
            if (!ok) bad++
        }
        END { exit (seen > 0 && bad == 0) ? 0 : 1 }
    ' /proc/self/uid_map /etc/subuid
}

check "user is vscode" test "$(id -un)" = vscode
check "graph root on the volume" info_is '{{.Store.GraphRoot}}' /var/lib/containers-rootless/vscode
check "native overlay" info_is '{{index .Store.GraphStatus "Native Overlay Diff"}}' true
check "pasta" default_network_is_pasta
check "runtime directory" runtime_dir_is_private
check "subuid inside the uid map" subuid_inside_map
check "run hello" podman run --rm quay.io/podman/hello
check "egress over pasta" podman run --rm quay.io/libpod/alpine:latest wget -q -O /dev/null https://quay.io/

reportResults
