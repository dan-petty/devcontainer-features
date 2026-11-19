#!/usr/bin/env bash
# Installs the Podman remote client and socat from the distribution archive, the
# entrypoint /usr/local/share/podman-init.sh and the start check
# /usr/local/share/podman-check.sh. The client uses the Podman engine of the host through
# the socket directory that the Feature mounts at /run/podman-host. No engine runs in the
# container. Runs as root when the dev container image is built.
set -e

FEATURE_ID=podman-outside-podman
FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARE_DIR="/usr/local/share/${FEATURE_ID}"

# shellcheck source=SCRIPTDIR/scripts/podman-common.sh
source "${FEATURE_DIR}/scripts/podman-common.sh"

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

# The remote user gets the client socket: through a link when it can use the host socket,
# else through the socat proxy and the group docker.
USERNAME="$(podman_common_remote_user "${_REMOTE_USER:-automatic}")"

podman_common_make_share_dir "${FEATURE_ID}"

# podman-remote depends only on libc6 and libsqlite3-0. socat is the proxy to the host
# socket when the remote user cannot use it.
podman_common_apt_update
podman_common_apt_install podman-remote socat

if [ "${COMPOSE}" = "podman-compose" ]; then
    podman_common_install_compose "${FEATURE_ID}"
fi

# dockerCompat: the docker command runs podman, which CONTAINER_HOST makes a client of the
# host engine. podman-docker pulls the podman package, but no engine process runs.
docker_sock_link=false
if [ "${DOCKERCOMPAT}" = "true" ] && ! podman_common_skip_docker_compat "${FEATURE_ID}"; then
    podman_common_install_podman_docker
    docker_sock_link=true
fi

# The socat proxy gives the client socket to the group docker, also without dockerCompat.
podman_common_docker_group "${USERNAME}"

# podman-docker installs /usr/bin/podman. The link makes podman-remote the podman command
# of the remote user with and without podman-docker. podman-compose runs this command.
ln -sfn /usr/bin/podman-remote /usr/local/bin/podman

install -m 0755 "${FEATURE_DIR}/podman-init.sh" /usr/local/share/podman-init.sh
install -m 0755 "${FEATURE_DIR}/podman-check.sh" /usr/local/share/podman-check.sh
cat > "${SHARE_DIR}/config" << EOF
PODMAN_USER=${USERNAME}
DOCKER_SOCK_LINK=${docker_sock_link}
EOF

podman_common_apt_clean

echo "${FEATURE_ID}: done. The remote user is ${USERNAME}."
