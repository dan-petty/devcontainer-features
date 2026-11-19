# shellcheck shell=bash
# Shared install steps of the podman-in-podman and podman-outside-podman Features.
# install.sh of each Feature sources this file. The two copies must stay byte-identical:
#   src/podman-in-podman/scripts/podman-common.sh
#   src/podman-outside-podman/scripts/podman-common.sh
# The file defines only functions. A function that takes FEATURE_ID uses it in its
# messages and file names.

# podman_common_require_root FEATURE_ID: stop when install.sh does not run as root.
podman_common_require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "(!) $1: install.sh must run as root." >&2
        exit 1
    fi
}

# podman_common_require_apt FEATURE_ID: stop when the image has no apt-get.
podman_common_require_apt() {
    if ! command -v apt-get > /dev/null 2>&1; then
        echo "(!) $1 supports only Debian and Ubuntu images: apt-get is missing." >&2
        exit 1
    fi
}

# podman_common_check_exclusion FEATURE_ID: stop when the other Podman Feature is
# installed. Each Feature checks for the other, so the second install stops in each order.
podman_common_check_exclusion() {
    local other=podman-in-podman
    if [ "$1" = "podman-in-podman" ]; then
        other=podman-outside-podman
    fi
    if [ -e "/usr/local/share/${other}" ]; then
        echo "(!) podman-in-podman and podman-outside-podman cannot be in one container." >&2
        exit 1
    fi
}

# podman_common_make_share_dir FEATURE_ID: make /usr/local/share/FEATURE_ID, which holds
# the config of the Feature. The other Podman Feature stops when this directory exists.
podman_common_make_share_dir() {
    mkdir -p "/usr/local/share/$1"
}

# podman_common_remote_user NAME: print the remote user. For "auto" and "automatic", take
# the first of vscode, node, codespace and the user with uid 1000 that exists, else root.
# For "none" or a user that does not exist, take root. The Features of
# devcontainers/features use the same rule.
podman_common_remote_user() {
    local candidate
    if [ "$1" = "auto" ] || [ "$1" = "automatic" ]; then
        for candidate in vscode node codespace "$(awk -F: '$3 == 1000 { print $1; exit }' /etc/passwd)"; do
            if [ -n "${candidate}" ] && id -u "${candidate}" > /dev/null 2>&1; then
                echo "${candidate}"
                return
            fi
        done
        echo root
    elif [ -z "$1" ] || [ "$1" = "none" ] || ! id -u "$1" > /dev/null 2>&1; then
        echo root
    else
        echo "$1"
    fi
}

# podman_common_apt_update: get the package lists of the distribution. The Features add
# no third-party repository.
podman_common_apt_update() {
    rm -rf /var/lib/apt/lists/*
    DEBIAN_FRONTEND=noninteractive apt-get update
}

# podman_common_apt_install PACKAGE...: install from the distribution archive, with no
# version pins and no recommended packages.
podman_common_apt_install() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

# podman_common_apt_clean: remove the package lists from the image.
podman_common_apt_clean() {
    rm -rf /var/lib/apt/lists/*
}

# podman_common_skip_docker_compat FEATURE_ID: return 0 and print one line when another
# Feature or package owns docker. Then dockerCompat installs no package, starts nothing
# and makes no link. podman-docker conflicts with docker-cli, docker.io and docker-ce-cli,
# and its install removes them.
podman_common_skip_docker_compat() {
    local docker_path
    # docker-in-docker and docker-outside-of-docker have this entrypoint, and their engine
    # owns /var/run/docker.sock.
    if [ -e /usr/local/share/docker-init.sh ]; then
        echo "(!) $1: /usr/local/share/docker-init.sh of another Feature is present. dockerCompat is skipped."
        return 0
    fi
    docker_path="$(command -v docker 2> /dev/null || true)"
    if [ -n "${docker_path}" ]; then
        docker_path="$(readlink -f "${docker_path}")"
        if ! dpkg -S "${docker_path}" 2> /dev/null | grep -q '^podman-docker:'; then
            echo "(!) $1: ${docker_path} is not the docker command of podman-docker. dockerCompat is skipped."
            return 0
        fi
    fi
    return 1
}

# podman_common_install_podman_docker: install podman-docker, whose docker command runs
# podman. The file /etc/containers/nodocker stops the message "Emulate Docker CLI using
# podman".
podman_common_install_podman_docker() {
    podman_common_apt_install podman-docker
    mkdir -p /etc/containers
    touch /etc/containers/nodocker
}

# podman_common_docker_group USER: make the system group docker when it is missing, and add
# the user. The group can use the Podman API socket. podman-docker makes no group.
podman_common_docker_group() {
    if ! getent group docker > /dev/null 2>&1; then
        groupadd --system docker
    fi
    if [ "$1" != "root" ]; then
        usermod -aG docker "$1"
    fi
}

# podman_common_install_compose FEATURE_ID: install podman-compose and make it the only
# compose provider. Then 'docker compose', 'podman compose' and podman-compose all run
# podman-compose. Without the file, 'podman compose' selects Docker Compose first when it
# is installed, and gives it a socket where no service can run.
podman_common_install_compose() {
    podman_common_apt_install podman-compose
    mkdir -p /etc/containers/containers.conf.d
    cat > "/etc/containers/containers.conf.d/50-$1-compose.conf" << EOF
# Written by the $1 Feature.
[engine]
compose_providers = ["podman-compose"]
compose_warning_logs = false
EOF
}
