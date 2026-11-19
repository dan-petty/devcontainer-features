#!/bin/bash
# podman-compose as vscode: two services find each other by name, and no API service runs.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

# The CLI can start the test before the entrypoint of the Feature ends.
check "entrypoint done" timeout 60 sh -c 'until [ -f /run/podman-in-podman/ready ]; do sleep 0.5; done'

no_api_service() { ! pgrep -f "podman system service"; }
finds() { "${@:3}" exec -T "$1" nslookup "$2" | grep "^Name:"; }

project=$(mktemp -d)
cat > "$project/compose.yaml" << 'COMPOSE'
services:
  first:
    image: quay.io/libpod/alpine:latest
    command: sleep 600
  second:
    image: quay.io/libpod/alpine:latest
    command: sleep 600
COMPOSE
cd "$project"

check "no API service" no_api_service
check "compose up" podman-compose up -d
check "first finds second" finds first second podman-compose
check "second finds first" finds second first podman-compose
check "still no API service" no_api_service
check "compose down" podman-compose down

reportResults
