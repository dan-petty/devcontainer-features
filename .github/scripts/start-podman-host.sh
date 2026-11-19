#!/usr/bin/env bash
# Starts the Podman API services of the runner. The tests of podman-outside-podman use
# them as the engine of the host:
#   /run/user/1000/podman/podman.sock    rootful service in the default mount source of
#                                        the Feature, for a host with no XDG_RUNTIME_DIR
#   /run/podman/podman.sock              rootful podman.socket of systemd (root:root 0660)
#   /run/user/<uid>/podman/podman.sock   rootless podman.socket of the runner user, set up
#                                        as NOTES.md tells for a host with systemd
# The services run until the end of the job.
set -euo pipefail

uid=$(id -u)
run_dir=/run/user/$uid

# sudo on the runner keeps XDG_RUNTIME_DIR. Rootful crun then writes its state to
# /run/user/<uid>/crun as root, and rootless crun of the user cannot use that directory.
as_root() { sudo env -u XDG_RUNTIME_DIR "$@"; }

sudo systemctl start podman.socket

sudo install -d -m 0755 /run/user/1000/podman
# shellcheck disable=SC2024 # The runner user opens the log, and the service writes to it.
as_root setsid -f podman system service --time=0 unix:///run/user/1000/podman/podman.sock \
    < /dev/null > "$RUNNER_TEMP/podman-rootful.log" 2>&1

# Linger starts the user manager of systemd, which makes the runtime directory of the
# user. The user unit podman.socket starts the service at the first connect.
sudo loginctl enable-linger "$(id -un)"
export XDG_RUNTIME_DIR=$run_dir
tries=0
until systemctl --user show-environment > /dev/null 2>&1; do
    if [ "$tries" -ge 60 ]; then
        echo "::error::The user manager of systemd did not start in 30 seconds."
        exit 1
    fi
    sleep 0.5
    tries=$((tries + 1))
done
systemctl --user start podman.socket
# The scenarios use ${localEnv:XDG_RUNTIME_DIR} in their mounts.
echo "XDG_RUNTIME_DIR=$run_dir" >> "$GITHUB_ENV"

for sock in /run/podman/podman.sock /run/user/1000/podman/podman.sock "$run_dir/podman/podman.sock"; do
    tries=0
    until sudo test -S "$sock"; do
        if [ "$tries" -ge 60 ]; then
            echo "::error::$sock did not appear in 30 seconds."
            cat "$RUNNER_TEMP/podman-rootful.log"
            exit 1
        fi
        sleep 0.5
        tries=$((tries + 1))
    done
    sudo stat -c '%n %U:%G %a' "$sock"
    as_root podman --url "unix://$sock" info \
        --format 'Podman {{.Version.Version}} rootless={{.Host.Security.Rootless}} network={{.Host.NetworkBackend}}'
    # The engine must also start a container, not only answer.
    if ! out=$(as_root podman --url "unix://$sock" run --rm quay.io/podman/hello 2>&1); then
        echo "::error::No container starts through $sock."
        printf '%s\n' "$out" | tail -n 5
        sudo ls -ldn /run/user "$run_dir" "$run_dir/crun" || true
        journalctl --user -u podman.service -n 20 --no-pager || true
        exit 1
    fi
done
