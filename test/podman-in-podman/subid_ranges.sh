#!/bin/bash
# podman-subid-ranges.sh against the map files in subid/.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

keepid=$(printf 'vscode:1:999\nvscode:1001:64535')
# ranges_are EXPECTED SUBID_FILE MAP_FILE
ranges_are() { [ "$(/usr/local/share/podman-subid-ranges.sh vscode 1000 "$2" "$3")" = "$1" ]; }
usage_error() { ! /usr/local/share/podman-subid-ranges.sh vscode 2> /dev/null; }

check "keep-id map gives two ranges" ranges_are "$keepid" subid/subuid subid/keepid_map
check "keep-id map with no range" ranges_are "$keepid" /dev/null subid/keepid_map
check "ranges inside the keep-id map stay" ranges_are "$keepid" subid/subuid_keepid subid/keepid_map
check "full map keeps the range" ranges_are vscode:100000:65536 subid/subuid subid/full_map
check "usage error" usage_error

reportResults
