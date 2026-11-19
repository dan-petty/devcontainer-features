#!/bin/bash
# podman-subid-ranges.sh against the map files in subid/.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

keepid=$(printf 'vscode:1:999\nvscode:1001:64535')
# With uid 1001 (ubuntu:noble keeps 1000 for the user ubuntu), each range stays inside one
# extent of the map. The kernel refuses a range that crosses two extents.
keepid_1001=$(printf 'vscode:1:999\nvscode:1000:1\nvscode:1002:64534')
# ranges_are EXPECTED SUBID_FILE MAP_FILE [ID]
ranges_are() { [ "$(/usr/local/share/podman-subid-ranges.sh vscode "${4:-1000}" "$2" "$3")" = "$1" ]; }
usage_error() { ! /usr/local/share/podman-subid-ranges.sh vscode 2> /dev/null; }

check "keep-id map gives two ranges" ranges_are "$keepid" subid/subuid subid/keepid_map
check "keep-id map with no range" ranges_are "$keepid" /dev/null subid/keepid_map
check "ranges inside the keep-id map stay" ranges_are "$keepid" subid/subuid_keepid subid/keepid_map
check "keep-id map with uid 1001" ranges_are "$keepid_1001" /dev/null subid/keepid_map 1001
check "a range across two extents is replaced" ranges_are "$keepid_1001" subid/subuid_cross_extents subid/keepid_map 1001
check "full map keeps the range" ranges_are vscode:100000:65536 subid/subuid subid/full_map
check "usage error" usage_error

reportResults
