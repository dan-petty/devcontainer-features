#!/bin/sh
# postStartCommand of the podman-outside-podman Feature. It runs as the remote user after
# each start of the container and tells whether the client reaches the Podman engine of
# the host. When a check fails, it prints the fix on the host and exits 1, and the Dev
# Containers CLI does not run the later start commands of the user.
CONFIG=/usr/local/share/podman-outside-podman/config
RUN_DIR=/run/podman-outside-podman
READY=$RUN_DIR/ready
LOG=$RUN_DIR/socat.log

fail() {
    echo "(!) podman-outside-podman: $1 See the output of /usr/local/share/podman-init.sh and $LOG." >&2
    exit 1
}

# The host engine does not answer. The fix is on the host.
fail_host() {
    cat >&2 << EOF
(!) podman-outside-podman: $1
    The container uses the Podman API socket in the directory that the Feature mounts at
    /run/podman-host. Start the Podman API service on the host:
      - With systemd (on WSL, set "[boot] systemd=true" in /etc/wsl.conf):
          systemctl --user enable --now podman.socket
          sudo loginctl enable-linger \$USER
      - Without systemd:
          podman system service --time=0 &
    For rootful Podman on the host, mount /run/podman at /run/podman-host. See the README
    of the Feature. The proxy log is $LOG.
EOF
    exit 1
}

[ -r "$CONFIG" ] || fail "cannot read $CONFIG."
# shellcheck source=/dev/null
. "$CONFIG"

# The Dev Containers CLI does not wait for the entrypoint. After a stop and a start, the
# marker of the last start can still be there, so the marker must hold the start time of
# the current PID 1 (field 22 of /proc/1/stat, as in podman-init.sh).
start_time=$(sed 's/.*) //' /proc/1/stat | cut -d' ' -f20)
[ -n "$start_time" ] || fail "cannot read the start time of PID 1 in /proc/1/stat."
tries=0
until [ "$(cat "$READY" 2> /dev/null)" = "$start_time" ]; do
    if [ "$tries" -ge 120 ]; then
        fail "the entrypoint did not end in 60 seconds after this start."
    fi
    sleep 0.5
    tries=$((tries + 1))
done

# Podman can write warnings to stderr when it works. Only stdout goes into the line, and
# stderr goes into the line only when a check fails.
err=$(mktemp) || fail "cannot make a temporary file."
trap 'rm -f "$err"' EXIT
# CONTAINER_HOST makes podman a client of the host engine.
if ! out=$(podman info --format '{{.Host.Security.Rootless}} {{.Version.Version}}' 2> "$err"); then
    fail_host "'podman info' through ${CONTAINER_HOST:-the default socket} failed: $(tail -n 1 "$err")."
fi
case "$out" in
    true\ *) mode=rootless ;;
    *) mode=rootful ;;
esac
summary="podman-outside-podman: $mode Podman ${out#* } on the host for $(id -un)."

# Only the link that the Feature made: docker-in-docker can own /var/run/docker.sock.
if [ "${DOCKER_SOCK_LINK:-false}" = "true" ]; then
    if ! out=$(podman --url unix:///var/run/docker.sock info --format '{{.Version.Version}}' 2> "$err"); then
        fail "'podman --url unix:///var/run/docker.sock info' failed: $(tail -n 1 "$err")."
    fi
    summary="$summary /var/run/docker.sock: Podman $out."
fi

echo "$summary"
