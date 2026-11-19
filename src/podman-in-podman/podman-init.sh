#!/bin/sh
# Entrypoint of the podman-in-podman Feature. It runs at each container start and
# prepares the container for rootful and rootless Podman. A second run changes nothing.
# With arguments, it runs them at the end, as the user that started the script.
set -e

SELF=/usr/local/share/podman-init.sh
CONFIG=/usr/local/share/podman-in-podman/config
SUBID_RANGES=/usr/local/share/podman-subid-ranges.sh
# All runtime files are in RUN_DIR. /run is not a tmpfs under Docker, so the files of the
# last start can still be there.
RUN_DIR=/run/podman-in-podman
# The Dev Containers CLI starts the entrypoints after the container prints "Container
# started", so the setup can still run when a tool starts. The marker tells that it ended.
# It holds the start time of PID 1, which is new at each start of the container.
READY=$RUN_DIR/ready
PID_FILE=$RUN_DIR/podman-service.pid
LOG=$RUN_DIR/podman-service.log
SOCK=/run/podman/podman.sock

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

# The marker of an earlier start is not valid for this start.
mkdir -p "$RUN_DIR"
rm -f "$READY"

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

    # d. A new volume is owned by root. The image can also hold the directory with an
    # old uid of the user: the Dev Containers CLI can change the uid after the build.
    # 'podman system migrate' below writes to this directory.
    mkdir -p "/var/lib/containers-rootless/$user"
    chown "$uid:$gid" "/var/lib/containers-rootless/$user"

    # e. The subordinate IDs must lie inside the ID map of this user namespace. A
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
            printf '%s\n' "$wanted" | sed 's/^/    /'
        fi
    }
    update_subids /etc/subuid "$uid" /proc/self/uid_map
    update_subids /etc/subgid "$gid" /proc/self/gid_map
    if [ "$subids_changed" = "true" ]; then
        runuser -u "$user" -- env HOME="$home" XDG_RUNTIME_DIR="$run_dir" podman system migrate ||
            echo "(!) podman-init.sh: 'podman system migrate' failed for $user." >&2
    fi
fi

# f. dockerCompat: the rootful Podman API service, as the dockerd of docker-in-docker.
# The group docker can use its socket. After a stop and a start of the container, the
# PID file and the socket of the last start can still be there, and the PID can now
# belong to a different process. So the service runs only when the command line of that
# PID is the service.
service_runs() {
    [ -f "$PID_FILE" ] || return 1
    pid=$(cat "$PID_FILE")
    case "$pid" in
        '' | *[!0-9]*) return 1 ;;
    esac
    # dash applies the redirections from left to right. With the input first, it prints
    # its error for a missing file before stderr goes to /dev/null.
    cmdline=$(tr '\0' ' ' 2> /dev/null < "/proc/$pid/cmdline") || return 1
    case "$cmdline" in
        "podman system service "*) return 0 ;;
    esac
    return 1
}
if [ "${DOCKER_SOCK_LINK:-false}" = "true" ]; then
    if ! service_runs; then
        # With the old socket in place, the wait below ends at once, and chgrp changes the
        # old file. The new service then makes its socket root:root 0600 again.
        rm -f "$SOCK" "$PID_FILE"
        mkdir -p "${SOCK%/*}"
        chmod 0755 "${SOCK%/*}"
        # shellcheck disable=SC2016 # sh -c expands $$, $1 and $2.
        setsid -f sh -c 'echo $$ > "$1" && exec podman system service --time=0 "unix://$2"' \
            sh "$PID_FILE" "$SOCK" < /dev/null > "$LOG" 2>&1
        tries=0
        while [ ! -S "$SOCK" ] && [ "$tries" -lt 60 ]; do
            sleep 0.5
            tries=$((tries + 1))
        done
        if [ -S "$SOCK" ]; then
            # Podman makes the socket root:root 0600.
            chgrp docker "$SOCK"
            chmod 0660 "$SOCK"
        else
            echo "(!) podman-init.sh: the Podman API service did not start in 30 seconds. See $LOG." >&2
        fi
    fi
    # The tmpfiles.d rule of podman-docker names the same link, but the image has no
    # systemd-tmpfiles.
    ln -sfn "$SOCK" /var/run/docker.sock
fi

# The start time of PID 1 is field 22 of /proc/1/stat. Field 2 can hold spaces, so the
# fields count from its ")". podman-check.sh reads the same value.
sed 's/.*) //' /proc/1/stat | cut -d' ' -f20 > "$READY"

finish "$@"
