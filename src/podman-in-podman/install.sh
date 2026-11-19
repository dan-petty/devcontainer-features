#!/usr/bin/env bash
# Installs Podman and its tools from the distribution archive, the configuration that
# nests Podman in a container, and the entrypoint /usr/local/share/podman-init.sh.
# Runs as root when the dev container image is built.
set -e

BUILDAH="${BUILDAH:-true}"
SKOPEO="${SKOPEO:-true}"
COMPOSE="${COMPOSE:-podman-compose}"
DOCKERCOMPAT="${DOCKERCOMPAT:-false}"
USERNAME="${_REMOTE_USER:-automatic}"

FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARE_DIR=/usr/local/share/podman-in-podman

if [ "$(id -u)" -ne 0 ]; then
    echo "(!) The podman-in-podman install script must run as root." >&2
    exit 1
fi

if ! command -v apt-get > /dev/null 2>&1; then
    echo "(!) podman-in-podman supports only Debian and Ubuntu images: apt-get is missing." >&2
    exit 1
fi

case "${COMPOSE}" in
    podman-compose | docker-compose | none) ;;
    *)
        echo "(!) The compose option must be podman-compose, docker-compose or none, not '${COMPOSE}'." >&2
        exit 1
        ;;
esac

# The remote user runs rootless Podman. 'automatic' takes the user with uid 1000, else root.
if [ "${USERNAME}" = "automatic" ] || [ "${USERNAME}" = "auto" ] || ! id -u "${USERNAME}" > /dev/null 2>&1; then
    USERNAME="$(awk -F: '$3 == 1000 { print $1; exit }' /etc/passwd)"
    USERNAME="${USERNAME:-root}"
fi

mkdir -p "${SHARE_DIR}"

# --no-install-recommends drops aardvark-dns (name resolution on Podman networks) and
# ca-certificates (image pulls over TLS). For rootful bridge networks, netavark 1.9 and
# later runs nft, and older netavark (ubuntu:noble has 1.4) runs iptables.
packages=(
    podman crun conmon netavark aardvark-dns nftables iptables passt uidmap catatonit
    containers-storage golang-github-containers-common fuse-overlayfs ca-certificates
)
if [ "${BUILDAH}" = "true" ]; then
    packages+=(buildah)
fi
if [ "${SKOPEO}" = "true" ]; then
    packages+=(skopeo)
fi

export DEBIAN_FRONTEND=noninteractive
rm -rf /var/lib/apt/lists/*
apt-get update

# Debian ships Compose version 2 as docker-compose. Ubuntu ships it as docker-compose-v2,
# and its docker-compose package is Compose version 1, which imports the distutils that
# Python 3.12 removed.
case "${COMPOSE}" in
    podman-compose) packages+=(podman-compose) ;;
    docker-compose)
        if apt-cache show docker-compose-v2 > /dev/null 2>&1; then
            packages+=(docker-compose-v2)
        else
            packages+=(docker-compose)
        fi
        ;;
esac

apt-get install -y --no-install-recommends "${packages[@]}"

# podman-docker conflicts with the Docker CLI packages. When another package has
# /usr/bin/docker (for example the docker-in-docker Feature), keep it and skip this option.
docker_compat_active=false
if [ "${DOCKERCOMPAT}" = "true" ]; then
    if [ -e /usr/bin/docker ] && ! dpkg -S /usr/bin/docker 2> /dev/null | grep -q '^podman-docker:'; then
        echo "(!) A docker CLI is present; dockerCompat is skipped"
    else
        apt-get install -y --no-install-recommends podman-docker
        # The file stops the message of podman-docker that the command is Podman, not Docker.
        touch /etc/containers/nodocker
        docker_compat_active=true
    fi
fi

# Podman already falls back to cgroupfs and the file event logger in a container without
# systemd. The file makes the choice fixed. Podman 4 uses slirp4netns for rootless networks
# by default, and Podman 5 uses pasta. pasta is the only one that is installed.
mkdir -p /etc/containers/containers.conf.d
cat > /etc/containers/containers.conf.d/50-podman-in-podman.conf << 'EOF'
# Written by the podman-in-podman Feature.
[engine]
cgroup_manager = "cgroupfs"
events_logger = "file"

[network]
default_rootless_network_cmd = "pasta"
EOF

# Rootless storage goes to a volume, not to the overlay root file system or the home
# directory. On the volume, rootless Podman uses native overlay and needs no /dev/fuse.
# containers/storage 1.57 (debian:trixie) and 1.51 (ubuntu:noble) read no drop-in
# directory, so the setting goes in /etc/containers/storage.conf. The file starts as a
# copy of the file of the distribution, as in the quay.io/podman/stable image.
if [ "${USERNAME}" != "root" ]; then
    storage_conf=/etc/containers/storage.conf
    if [ ! -f "${storage_conf}" ]; then
        cp /usr/share/containers/storage.conf "${storage_conf}"
    fi
    sed -i -e '/^[[:space:]]*rootless_storage_path[[:space:]]*=/d' \
        -e "/^\[storage\][[:space:]]*\$/a rootless_storage_path = \"/var/lib/containers-rootless/${USERNAME}\"" \
        "${storage_conf}"
    if ! grep -q '^rootless_storage_path = ' "${storage_conf}"; then
        echo "(!) ${storage_conf} has no [storage] table: cannot set rootless_storage_path." >&2
        exit 1
    fi
    mkdir -p "/var/lib/containers-rootless/${USERNAME}"
    # In its rootless network namespace, Podman 4 (ubuntu:noble) mounts a private
    # directory on /var/lib/cni, or on /var/lib when /var/lib/cni is absent. On /var/lib,
    # the mount hides the rootless storage, and Podman finds no user network.
    mkdir -p /var/lib/cni
    chown "${USERNAME}:" "/var/lib/containers-rootless/${USERNAME}"
fi

# The API socket service starts at container start when a tool needs it.
start_socket=false
if [ "${docker_compat_active}" = "true" ] || [ "${COMPOSE}" = "docker-compose" ]; then
    start_socket=true
fi

install -m 0755 "${FEATURE_DIR}/podman-init.sh" /usr/local/share/podman-init.sh
install -m 0755 "${FEATURE_DIR}/podman-subid-ranges.sh" /usr/local/share/podman-subid-ranges.sh
cat > "${SHARE_DIR}/config" << EOF
PODMAN_USER=${USERNAME}
PODMAN_SOCKET=${start_socket}
PODMAN_DOCKER_LINK=${docker_compat_active}
EOF

rm -rf /var/lib/apt/lists/*

echo "podman-in-podman: done. The remote user is ${USERNAME}."
