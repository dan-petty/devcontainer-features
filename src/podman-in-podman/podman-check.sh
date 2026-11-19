#!/bin/sh
# postStartCommand of the podman-in-podman Feature. It runs as the remote user after each
# start of the container and tells whether Podman works. When a check fails, it exits 1,
# and the Dev Containers CLI does not run the later start commands of the user.
CONFIG=/usr/local/share/podman-in-podman/config
RUN_DIR=/run/podman-in-podman
READY=$RUN_DIR/ready
LOG=$RUN_DIR/podman-service.log

fail() {
    echo "(!) podman-in-podman: $1 See the output of /usr/local/share/podman-init.sh and $LOG." >&2
    exit 1
}

[ -r "$CONFIG" ] || fail "cannot read $CONFIG."
# shellcheck source=/dev/null
. "$CONFIG"

# The Dev Containers CLI does not wait for the entrypoint.
tries=0
while [ ! -f "$READY" ]; do
    if [ "$tries" -ge 120 ]; then
        fail "the entrypoint did not end in 60 seconds."
    fi
    sleep 0.5
    tries=$((tries + 1))
done

if [ "$(id -u)" -eq 0 ]; then
    mode=rootful
else
    mode=rootless
fi
# Podman can write warnings to stderr when it works. Only stdout goes into the line, and
# stderr goes into the line only when a check fails.
err=$(mktemp) || fail "cannot make a temporary file."
trap 'rm -f "$err"' EXIT
if ! out=$(podman info --format '{{.Version.Version}}' 2> "$err"); then
    fail "'podman info' failed: $(tail -n 1 "$err")."
fi
summary="podman-in-podman: $mode Podman $out for $(id -un)."

# Only the socket that the Feature made: docker-in-docker can own /var/run/docker.sock.
# The docker command runs local Podman, so the check uses podman --url.
if [ "${DOCKER_SOCK_LINK:-false}" = "true" ]; then
    if ! out=$(podman --url unix:///var/run/docker.sock info --format '{{.Version.Version}}' 2> "$err"); then
        fail "'podman --url unix:///var/run/docker.sock info' failed: $(tail -n 1 "$err")."
    fi
    summary="$summary /var/run/docker.sock: rootful Podman $out."
fi

echo "$summary"
