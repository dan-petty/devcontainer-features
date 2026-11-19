#!/usr/bin/env bash
# Installs Podman and its tools from the distribution archive, the configuration that
# nests Podman in a container, the entrypoint /usr/local/share/podman-init.sh and the
# start check /usr/local/share/podman-check.sh. Runs as root when the dev container image
# is built.
set -e

FEATURE_ID=podman-in-podman
FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARE_DIR="/usr/local/share/${FEATURE_ID}"

# shellcheck source=SCRIPTDIR/scripts/podman-common.sh
source "${FEATURE_DIR}/scripts/podman-common.sh"

BUILDAH="${BUILDAH:-true}"
SKOPEO="${SKOPEO:-true}"
COMPOSE="${COMPOSE:-podman-compose}"
DOCKERCOMPAT="${DOCKERCOMPAT:-false}"

podman_common_require_root "${FEATURE_ID}"
podman_common_check_exclusion "${FEATURE_ID}"
podman_common_require_apt "${FEATURE_ID}"

case "${COMPOSE}" in
    podman-compose | none) ;;
    *)
        echo "(!) ${FEATURE_ID}: the compose option must be podman-compose or none, not '${COMPOSE}'." >&2
        exit 1
        ;;
esac

# The remote user runs rootless Podman.
USERNAME="$(podman_common_remote_user "${_REMOTE_USER:-automatic}")"

podman_common_make_share_dir "${FEATURE_ID}"

# --no-install-recommends drops aardvark-dns (name resolution on Podman networks) and
# ca-certificates (image pulls over TLS). For rootful bridge networks, netavark 1.9 and
# later runs nft, and older netavark (ubuntu:noble has 1.4) runs iptables. Podman 4
# (ubuntu:noble) starts the rootless network namespace of a user network with slirp4netns.
# After one rootless run without slirp4netns, a later install of it does not repair the
# network, so the package must be in the image.
packages=(
    podman crun conmon netavark aardvark-dns nftables iptables passt slirp4netns uidmap
    catatonit containers-storage golang-github-containers-common fuse-overlayfs
    ca-certificates
)
if [ "${BUILDAH}" = "true" ]; then
    packages+=(buildah)
fi
if [ "${SKOPEO}" = "true" ]; then
    packages+=(skopeo)
fi

podman_common_apt_update
podman_common_apt_install "${packages[@]}"

if [ "${COMPOSE}" = "podman-compose" ]; then
    podman_common_install_compose "${FEATURE_ID}"
fi

# dockerCompat: the docker command runs podman, and /var/run/docker.sock is the socket of
# a rootful Podman API service that the entrypoint starts.
docker_sock_link=false
if [ "${DOCKERCOMPAT}" = "true" ] && ! podman_common_skip_docker_compat "${FEATURE_ID}"; then
    podman_common_install_podman_docker
    podman_common_docker_group "${USERNAME}"
    docker_sock_link=true
fi

# Podman already falls back to cgroupfs and the file event logger in a container without
# systemd. The file makes the choice fixed. Podman 5 uses pasta for the network of a
# rootless container by default, and Podman 4 uses slirp4netns. The file sets pasta for
# each version.
mkdir -p /etc/containers/containers.conf.d
cat > "/etc/containers/containers.conf.d/50-${FEATURE_ID}.conf" << EOF
# Written by the ${FEATURE_ID} Feature.
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
        echo "(!) ${FEATURE_ID}: ${storage_conf} has no [storage] table: cannot set rootless_storage_path." >&2
        exit 1
    fi
    mkdir -p "/var/lib/containers-rootless/${USERNAME}"
    # In its rootless network namespace, Podman 4 (ubuntu:noble) mounts a private
    # directory on /var/lib/cni, or on /var/lib when /var/lib/cni is absent. On /var/lib,
    # the mount hides the rootless storage, and Podman finds no user network.
    mkdir -p /var/lib/cni
    chown "${USERNAME}:" "/var/lib/containers-rootless/${USERNAME}"
fi

install -m 0755 "${FEATURE_DIR}/podman-init.sh" /usr/local/share/podman-init.sh
install -m 0755 "${FEATURE_DIR}/podman-check.sh" /usr/local/share/podman-check.sh
install -m 0755 "${FEATURE_DIR}/podman-subid-ranges.sh" /usr/local/share/podman-subid-ranges.sh
cat > "${SHARE_DIR}/config" << EOF
PODMAN_USER=${USERNAME}
DOCKER_SOCK_LINK=${docker_sock_link}
EOF

podman_common_apt_clean

echo "${FEATURE_ID}: done. The remote user is ${USERNAME}."
