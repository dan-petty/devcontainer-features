#!/bin/bash
# dockerCompat as vscode: docker runs rootless Podman, docker compose runs podman-compose,
# and /var/run/docker.sock is the socket of rootful Podman. No Docker CLI is installed.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "podman-check" /usr/local/share/podman-check.sh

docker_from_podman_docker() { dpkg -S /usr/bin/docker | grep '^podman-docker:'; }
no_docker_cli_package() {
    local package
    for package in docker-cli docker.io docker-ce-cli; do
        if [ "$(dpkg-query -W -f="\${db:Status-Status}" "$package" 2> /dev/null)" = installed ]; then
            echo "$package is installed"
            return 1
        fi
    done
}
names_podman_engine() { docker version | grep 'Podman Engine'; }
link_to_rootful_socket() { [ "$(readlink /var/run/docker.sock)" = /run/podman/podman.sock ]; }
socket_mode() { [ "$(stat -c '%U:%G %a' /run/podman/podman.sock)" = "root:docker 660" ]; }
socket_is_rootful() { [ "$(podman --url unix:///var/run/docker.sock info --format '{{.Host.Security.Rootless}}')" = false ]; }
running_services() { podman ps --filter status=running --format '{{.Names}}' | grep -c '^pinp[-_]'; }
two_services_run() { [ "$(running_services)" = 2 ]; }
no_services() { ! podman ps -a --format '{{.Names}}' | grep '^pinp[-_]'; }
not_in_rootful_store() { ! sudo podman image exists localhost/pinp-docker-build; }

check "docker is from podman-docker" docker_from_podman_docker
check "no Docker CLI package" no_docker_cli_package
check "nodocker file" test -f /etc/containers/nodocker
check "docker version names Podman Engine" names_podman_engine
check "docker.sock links to the rootful socket" link_to_rootful_socket
check "socket is root:docker 660" socket_mode
check "socket is rootful Podman" socket_is_rootful

# The directory name is the compose project name.
project="$(mktemp -d)/pinp"
mkdir "$project"
# As PID 1, sleep ignores SIGTERM. The init process (catatonit) stops it at once, so down
# does not wait 10 seconds for each container.
cat > "$project/compose.yaml" << 'COMPOSE'
services:
  a:
    image: quay.io/libpod/alpine:latest
    init: true
    command: sleep 600
  b:
    image: quay.io/libpod/alpine:latest
    init: true
    command: sleep 600
COMPOSE
cd "$project"

# podman-compose 1.0.6 (ubuntu:noble) exits 0 when a container does not start, so the
# checks look at the containers, not at the exit status of up and down.
docker compose up -d || echo "docker compose up failed"
check "two services run" two_services_run
check "b finds a by name" docker compose exec -T b ping -c1 -W5 a
docker compose down || echo "docker compose down failed"
check "down removes the services" no_services

context=$(mktemp -d)
printf 'FROM quay.io/libpod/alpine:latest\nRUN touch /built\n' > "$context/Dockerfile"
check "docker build" docker build -t localhost/pinp-docker-build "$context"
check "image in the rootless store" podman image exists localhost/pinp-docker-build
check "image not in the rootful store" not_in_rootful_store

reportResults
