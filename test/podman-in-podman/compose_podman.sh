#!/bin/bash
# The defaults as vscode: podman compose runs podman-compose, two services find each other
# by name, and no API service runs.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "podman-check" /usr/local/share/podman-check.sh

# The command line of each process. grep does not match itself: its line starts with grep.
api_service_runs() {
    local cmdline
    for cmdline in /proc/[0-9]*/cmdline; do
        tr '\0' ' ' < "$cmdline" 2> /dev/null
        echo
    done | grep '^podman system service'
}
no_api_service() { ! api_service_runs; }
provider_is_podman_compose() { podman compose version | grep 'podman-compose'; }
running_services() { podman ps --filter status=running --format '{{.Names}}' | grep -c '^pinp[-_]'; }
two_services_run() { [ "$(running_services)" = 2 ]; }
no_services() { ! podman ps -a --format '{{.Names}}' | grep '^pinp[-_]'; }

check "compose drop-in" test -f /etc/containers/containers.conf.d/50-podman-in-podman-compose.conf
check "podman compose runs podman-compose" provider_is_podman_compose
check "no API service" no_api_service

# The directory name is the compose project name.
project="$(mktemp -d)/pinp"
mkdir "$project"
cat > "$project/compose.yaml" << 'COMPOSE'
services:
  a:
    image: quay.io/libpod/alpine:latest
    command: sleep 600
  b:
    image: quay.io/libpod/alpine:latest
    command: sleep 600
COMPOSE
cd "$project"

# podman-compose 1.0.6 (ubuntu:noble) exits 0 when a container does not start, so the
# checks look at the containers, not at the exit status of up and down.
podman compose up -d || echo "podman compose up failed"
check "two services run" two_services_run
check "b finds a by name" podman compose exec -T b ping -c1 -W5 a
check "still no API service" no_api_service
podman compose down || echo "podman compose down failed"
check "down removes the services" no_services

reportResults
