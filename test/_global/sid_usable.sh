#!/bin/bash
# This scenario installs the common upstream Features and podman-in-podman in one debian:sid container.
# The weekly run of test-all.yaml runs this scenario. Thus a change in debian:sid that
# breaks one of the Features fails that run. The claude-code Feature fails alone on
# debian:sid. Its installsAfter puts it after node:2.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "user is vscode" test "$(id -un)" = vscode
check "zsh" zsh --version
check "git" git --version
check "node" node --version
check "npm" npm --version
check "gh" gh --version
check "copilot" copilot --version
check "claude" claude --version
check "podman-check" /usr/local/share/podman-check.sh
check "podman" podman --version
check "podman is rootless" test "$(podman info --format '{{.Host.Security.Rootless}}')" = true
check "rootless run hello" podman run --rm quay.io/podman/hello

reportResults
