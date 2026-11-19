#!/bin/bash
# dockerCompat as vscode: docker runs podman as a client of the host engine, docker compose
# runs podman-compose, and /var/run/docker.sock links to the client socket. No Docker CLI
# is installed, and all tools use one store: the host engine.
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
server_is_podman() { docker version | grep -E '^Server: +Podman Engine'; }
docker_info_is_remote() { [ "$(docker info --format '{{.Host.ServiceIsRemote}}')" = true ]; }
link_to_client_socket() { [ "$(readlink /var/run/docker.sock)" = /run/podman/podman.sock ]; }
socket_mode() { [ "$(stat -c '%F %U:%G %a' /run/podman/podman.sock)" = "socket root:docker 660" ]; }
docker_sock_reaches_host() { [ "$(podman --url unix:///var/run/docker.sock info --format '{{.Host.ServiceIsRemote}}')" = true ]; }
sudo_podman_remote_is_remote() { [ "$(sudo podman-remote info --format '{{.Host.ServiceIsRemote}}')" = true ]; }
running_services() { podman ps --filter status=running --format '{{.Names}}' | grep -c '^popp[-_]'; }
two_services_run() { [ "$(running_services)" = 2 ]; }
no_services() { ! podman ps -a --format '{{.Names}}' | grep '^popp[-_]'; }

check "docker is from podman-docker" docker_from_podman_docker
check "no Docker CLI package" no_docker_cli_package
check "nodocker file" test -f /etc/containers/nodocker
check "docker version shows a Podman server" server_is_podman
check "docker info reports a remote engine" docker_info_is_remote
check "docker.sock links to the client socket" link_to_client_socket
check "socket is root:docker 660" socket_mode
check "docker.sock reaches the host engine" docker_sock_reaches_host
check "sudo podman-remote reaches the host engine" sudo_podman_remote_is_remote

# The directory name is the compose project name.
project="$(mktemp -d)/popp"
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
check "docker build" docker build -t localhost/popp-docker-build "$context"
check "podman finds the image (one store)" podman image exists localhost/popp-docker-build
podman rmi -f localhost/popp-docker-build > /dev/null || echo "podman rmi failed"

reportResults
