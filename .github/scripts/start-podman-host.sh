#!/usr/bin/env bash
# Starts the Podman API services of the runner. The tests of podman-outside-podman use
# them as the engine of the host:
#   /run/user/1000/podman/podman.sock    rootful service in the default mount source of
#                                        the Feature, for a host with no XDG_RUNTIME_DIR
#   /run/podman/podman.sock              rootful podman.socket of systemd (root:root 0660)
#   $XDG_RUNTIME_DIR/podman/podman.sock  rootless service of the runner user (uid 1001)
# The services run until the end of the job.
set -euo pipefail

run_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    # The scenarios use ${localEnv:XDG_RUNTIME_DIR} in their mounts.
    echo "XDG_RUNTIME_DIR=$run_dir" >> "$GITHUB_ENV"
fi
if [ ! -d "$run_dir" ]; then
    sudo install -d -m 0700 -o "$(id -u)" -g "$(id -g)" "$run_dir"
fi

sudo systemctl start podman.socket

sudo install -d -m 0755 /run/user/1000/podman
# shellcheck disable=SC2024 # The runner user opens the log, and the service writes to it.
sudo setsid -f podman system service --time=0 unix:///run/user/1000/podman/podman.sock \
    < /dev/null > "$RUNNER_TEMP/podman-rootful.log" 2>&1

mkdir -p "$run_dir/podman"
XDG_RUNTIME_DIR="$run_dir" setsid -f podman system service --time=0 "unix://$run_dir/podman/podman.sock" \
    < /dev/null > "$RUNNER_TEMP/podman-rootless.log" 2>&1

for sock in /run/podman/podman.sock /run/user/1000/podman/podman.sock "$run_dir/podman/podman.sock"; do
    tries=0
    until sudo test -S "$sock"; do
        if [ "$tries" -ge 60 ]; then
            echo "::error::$sock did not appear in 30 seconds."
            cat "$RUNNER_TEMP"/podman-*.log
            exit 1
        fi
        sleep 0.5
        tries=$((tries + 1))
    done
    sudo stat -c '%n %U:%G %a' "$sock"
    sudo podman --url "unix://$sock" info \
        --format 'Podman {{.Version.Version}} rootless={{.Host.Security.Rootless}} network={{.Host.NetworkBackend}}'
done

# Docker on the runner sets the policy of the FORWARD chain. With br_netfilter, it also
# applies to the bridge networks of rootful Podman.
echo "FORWARD policy: $(sudo iptables -S FORWARD 2> /dev/null | head -n 1)"
echo "bridge-nf-call-iptables: $(cat /proc/sys/net/bridge/bridge-nf-call-iptables 2> /dev/null || echo 'no br_netfilter')"
