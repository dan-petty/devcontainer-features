#!/bin/sh
# Entrypoint of the podman-in-podman Feature. It runs at each container start and
# prepares the container for rootful and rootless Podman. A second run changes nothing.
# With arguments, it runs them at the end, as the user that started the script.
set -e

SELF=/usr/local/share/podman-init.sh
CONFIG=/usr/local/share/podman-in-podman/config
SUBID_RANGES=/usr/local/share/podman-subid-ranges.sh

finish() {
    if [ "$#" -gt 0 ]; then
        exec "$@"
    fi
    exit 0
}

# The setup needs root. Rootless Podman with --userns=keep-id starts the container as
# the host user, so the script then runs the setup through sudo.
if [ "$(id -u)" -ne 0 ]; then
    sudo -n "$SELF" true || echo "(!) podman-init.sh: the setup needs root or sudo with no password. Podman can fail." >&2
    finish "$@"
fi

# shellcheck source=/dev/null
. "$CONFIG"
user=${PODMAN_USER:-root}

# a. Make the root mount shared, as moby hack/dind does. Rootless Podman otherwise
# warns that "/" is not a shared mount.
mount --make-rshared / || echo "(!) podman-init.sh: cannot make / a shared mount." >&2

# b. cgroup v2 nesting, as in docker-init.sh of the docker-in-docker Feature. Move each
# process out of the root cgroup, then give the controllers to the child cgroups. This
# must come before the first podman command: after it, the root cgroup can be
# "domain threaded", and the memory controller cannot be enabled.
controllers=$(cat /sys/fs/cgroup/cgroup.controllers 2> /dev/null || true)
set_cgroup_nesting() {
    mkdir -p /sys/fs/cgroup/init
    xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs 2> /dev/null || :
    echo "$controllers" | sed -e 's/ / +/g' -e 's/^/+/' > /sys/fs/cgroup/cgroup.subtree_control
}
if [ -n "$controllers" ]; then
    tries=0
    until set_cgroup_nesting 2> /dev/null; do
        tries=$((tries + 1))
        if [ "$tries" -ge 5 ]; then
            echo "(!) podman-init.sh: cgroup v2 nesting failed. Resource limits of rootful Podman can fail." >&2
            break
        fi
        echo "(*) podman-init.sh: cgroup v2 nesting failed, retrying..."
    done
fi

if [ "$user" != "root" ]; then
    uid=$(id -u "$user")
    gid=$(id -g "$user")
    home=$(getent passwd "$user" | cut -d: -f6)
    run_dir=/run/user/$uid

    # c. Rootful Podman makes /run/user with mode 0700. Rootless Podman then cannot
    # reach its runtime directory.
    mkdir -p "$run_dir"
    chmod 0755 /run/user
    chown "$uid:$gid" "$run_dir"
    chmod 0700 "$run_dir"

    # d. The subordinate IDs must lie inside the ID map of this user namespace. A
    # container of rootless Podman with --userns=keep-id maps only about 65536 IDs.
    subids_changed=false
    update_subids() { # FILE ID MAP
        wanted=$("$SUBID_RANGES" "$user" "$2" "$1" "$3")
        current=$(awk -F: -v u="$user" -v o="$uid" '$1 == u || $1 == o' "$1" 2> /dev/null || true)
        if [ "$wanted" != "$current" ]; then
            {
                awk -F: -v u="$user" -v o="$uid" '$1 != u && $1 != o' "$1" 2> /dev/null || true
                printf '%s\n' "$wanted"
            } > "$1.podman-init"
            chmod 0644 "$1.podman-init"
            mv "$1.podman-init" "$1"
            subids_changed=true
            echo "(*) podman-init.sh: wrote the ranges of $user to $1:"
            printf '    %s\n' "$wanted"
        fi
    }
    update_subids /etc/subuid "$uid" /proc/self/uid_map
    update_subids /etc/subgid "$gid" /proc/self/gid_map
    if [ "$subids_changed" = "true" ]; then
        runuser -u "$user" -- env HOME="$home" XDG_RUNTIME_DIR="$run_dir" podman system migrate ||
            echo "(!) podman-init.sh: 'podman system migrate' failed for $user." >&2
    fi

    # e. A new volume is owned by root.
    mkdir -p "/var/lib/containers-rootless/$user"
    chown "$uid:$gid" "/var/lib/containers-rootless/$user"
fi

# f. The API socket for docker-compose and the docker CLI.
if [ "${PODMAN_SOCKET:-false}" = "true" ]; then
    if [ "$user" = "root" ]; then
        sock_dir=/run/podman
    else
        sock_dir=$run_dir/podman
    fi
    sock=$sock_dir/podman.sock
    pid_file=$sock_dir/podman-init.pid
    if ! { [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2> /dev/null; }; then
        mkdir -p "$sock_dir"
        # shellcheck disable=SC2016 # sh -c expands $$, $1 and $2.
        service='echo $$ > "$1" && exec podman system service --time=0 "unix://$2"'
        if [ "$user" = "root" ]; then
            setsid -f sh -c "$service" sh "$pid_file" "$sock" < /dev/null > /tmp/podman-service.log 2>&1
        else
            chown "$uid:$gid" "$sock_dir"
            setsid -f runuser -u "$user" -- env HOME="$home" XDG_RUNTIME_DIR="$run_dir" \
                sh -c "$service" sh "$pid_file" "$sock" < /dev/null > /tmp/podman-service.log 2>&1
        fi
        tries=0
        while [ ! -S "$sock" ] && [ "$tries" -lt 20 ]; do
            sleep 0.5
            tries=$((tries + 1))
        done
    fi
    if [ "${PODMAN_DOCKER_LINK:-false}" = "true" ]; then
        ln -sfn "$sock" /var/run/docker.sock
    fi
fi

finish "$@"
