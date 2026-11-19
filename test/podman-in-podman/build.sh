#!/bin/bash
# Rootless and rootful podman build with a user ID above 1000, with the default isolation.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

context=$(mktemp -d)
cat > "$context/Containerfile" << 'CONTAINERFILE'
FROM quay.io/libpod/alpine:latest
RUN adduser -D -u 2000 app && mkdir /data && chown app /data
CONTAINERFILE

owner_is_2000() { [ "$("$@" run --rm localhost/pinp-build stat -c %u /data)" = 2000 ]; }

check "rootless build" podman build -t localhost/pinp-build "$context"
check "rootless owner 2000" owner_is_2000 podman
check "rootful build" sudo podman build -t localhost/pinp-build "$context"
check "rootful owner 2000" owner_is_2000 sudo podman

reportResults
