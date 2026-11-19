#!/bin/bash
# compose=docker-compose with dockerCompat: the docker command and the socket are Podman.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

# The CLI can start the test before the entrypoint of the Feature ends.
check "entrypoint done" timeout 60 sh -c 'until [ -f /run/podman-in-podman/ready ]; do sleep 0.5; done'

finds() { "${@:3}" exec -T "$1" nslookup "$2" | grep "^Name:"; }
names_podman() { "$@" | grep Podman; }

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

check "podman-docker" dpkg -s podman-docker
check "nodocker file" test -f /etc/containers/nodocker
check "docker version names Podman" names_podman docker version
check "docker.sock is a link" test -L /var/run/docker.sock
check "socket server is Podman" names_podman curl -fsS --unix-socket /var/run/docker.sock http://d/version
check "compose up" docker compose up -d
check "first finds second" finds first second docker compose
check "compose down" docker compose down

reportResults
