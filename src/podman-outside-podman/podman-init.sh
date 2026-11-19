#!/bin/sh
# Entrypoint of the podman-outside-podman Feature. It runs at each container start and
# makes the client socket /run/podman/podman.sock for the Podman engine of the host. A
# second run changes nothing. With arguments, it runs them at the end, as the user that
# started the script.
set -e

SELF=/usr/local/share/podman-init.sh
CONFIG=/usr/local/share/podman-outside-podman/config
# All runtime files are in RUN_DIR. /run is not a tmpfs under Docker, so the files of the
# last start can still be there.
RUN_DIR=/run/podman-outside-podman
# The Dev Containers CLI starts the entrypoints after the container prints "Container
# started", so the setup can still run when a tool starts. The marker tells that it ended.
# It holds the start time of PID 1, which is new at each start of the container.
READY=$RUN_DIR/ready
PID_FILE=$RUN_DIR/socat.pid
LOG=$RUN_DIR/socat.log
# The Feature mounts the socket directory of the host here. A directory bind follows the
# host when it makes the socket again, and a file bind keeps the old socket.
HOST_SOCK=/run/podman-host/podman.sock
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
    sudo -n "$SELF" true || echo "(!) podman-init.sh: the setup needs root or sudo with no password. The client socket can be missing." >&2
    finish "$@"
fi

# shellcheck source=/dev/null
. "$CONFIG"
user=${PODMAN_USER:-root}

# The marker of an earlier start is not valid for this start.
mkdir -p "$RUN_DIR"
rm -f "$READY"
mkdir -p "${SOCK%/*}"
chmod 0755 "${SOCK%/*}"

# After a stop and a start of the container, the PID file of the last start can still be
# there, and the PID can now belong to a different process. So the proxy runs only when
# the command line of that PID is socat.
proxy_runs() {
    [ -f "$PID_FILE" ] || return 1
    pid=$(cat "$PID_FILE")
    case "$pid" in
        '' | *[!0-9]*) return 1 ;;
    esac
    # dash applies the redirections from left to right. With the input first, it prints
    # its error for a missing file before stderr goes to /dev/null.
    cmdline=$(tr '\0' ' ' 2> /dev/null < "/proc/$pid/cmdline") || return 1
    case "$cmdline" in
        "socat "*) return 0 ;;
    esac
    return 1
}

# A connect to a Unix socket needs write permission on it. The test makes no API call, so
# a host engine that is not ready does not stop the start.
if runuser -u "$user" -- test -w "$HOST_SOCK"; then
    # The direct case, for example rootless Podman with --userns=keep-id on the host: the
    # user owns the host socket, so a link is sufficient.
    if proxy_runs; then
        kill "$pid" || true
    fi
    rm -f "$PID_FILE"
    if [ ! -L "$SOCK" ] || [ "$(readlink "$SOCK")" != "$HOST_SOCK" ]; then
        rm -f "$SOCK"
        ln -s "$HOST_SOCK" "$SOCK"
    fi
elif ! proxy_runs; then
    # The proxy case: a rootful socket, a socket of a different uid, or no socket yet.
    # socat does not listen on a path that exists, and the old socket or link of the last
    # start can still be there.
    rm -f "$SOCK" "$PID_FILE"
    # shellcheck disable=SC2016 # sh -c expands $$, $1, $2 and $3.
    setsid -f sh -c 'echo $$ > "$1" && exec socat "UNIX-LISTEN:$2,fork,user=root,group=docker,mode=660" "UNIX-CONNECT:$3"' \
        sh "$PID_FILE" "$SOCK" "$HOST_SOCK" < /dev/null > "$LOG" 2>&1
    tries=0
    while [ ! -S "$SOCK" ] && [ "$tries" -lt 60 ]; do
        sleep 0.5
        tries=$((tries + 1))
    done
    if [ ! -S "$SOCK" ]; then
        echo "(!) podman-init.sh: the socat proxy did not start in 30 seconds. See $LOG." >&2
    fi
fi

# dockerCompat: the tmpfiles.d rule of podman-docker names the same link, but the image
# has no systemd-tmpfiles.
if [ "${DOCKER_SOCK_LINK:-false}" = "true" ]; then
    ln -sfn "$SOCK" /var/run/docker.sock
fi

# The start time of PID 1 is field 22 of /proc/1/stat. Field 2 can hold spaces, so the
# fields count from its ")". podman-check.sh reads the same value.
sed 's/.*) //' /proc/1/stat | cut -d' ' -f20 > "$READY"

finish "$@"
