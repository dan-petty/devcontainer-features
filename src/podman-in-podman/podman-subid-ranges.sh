#!/bin/sh
# Usage: podman-subid-ranges.sh USER ID [SUBID_FILE [MAP_FILE]]
#
# Prints the lines USER:START:COUNT that SUBID_FILE (default /etc/subuid) must hold for
# USER, so that rootless Podman can use them in this user namespace. MAP_FILE (default
# /proc/self/uid_map) is the ID map of the namespace. ID is the user's own ID (the uid
# for /etc/subuid, the gid for /etc/subgid).
#
# The kernel maps a subordinate range only when the range lies inside one line (extent)
# of MAP_FILE. When each range of USER in SUBID_FILE lies inside one extent, the script
# prints these ranges again. Otherwise, it prints each extent of MAP_FILE, cut to the IDs
# 1 to 65535 and without ID. With the keep-id map "0 1 1000 / 1000 0 1 / 1001 1001 64536"
# and ID 1000, that gives 1:999 and 1001:64535, the same ranges as the
# quay.io/podman/stable image. With ID 1001, it gives 1:999, 1000:1 and 1002:64534.
set -e

if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
    echo "Usage: $0 USER ID [SUBID_FILE [MAP_FILE]]" >&2
    exit 2
fi

user=$1
id=$2
subid_file=${3:-/etc/subuid}
map_file=${4:-/proc/self/uid_map}
owner_uid=$(id -u "$user" 2> /dev/null || echo "$user")

if [ ! -e "$subid_file" ]; then
    subid_file=/dev/null
fi

# Each map line is "INSIDE OUTSIDE COUNT". Only the inside IDs are visible here.
sort -n -k1,1 "$map_file" | awk -v user="$user" -v owner="$owner_uid" -v id="$id" \
    -v subid_file="$subid_file" '
    # The inside IDs of each extent, sorted: [lo[i], hi[i]].
    NF >= 3 {
        n++
        lo[n] = $1 + 0
        hi[n] = $1 + $3 - 1
    }

    function mapped(start, end,    i) {
        for (i = 1; i <= n; i++) {
            if (start >= lo[i] && end <= hi[i]) return 1
        }
        return 0
    }

    function emit(start, end) {
        if (start <= end) print user ":" start ":" (end - start + 1)
    }

    END {
        kept = 0
        inside = 1
        while ((getline line < subid_file) > 0) {
            split(line, f, ":")
            if (f[1] != user && f[1] != owner) continue
            kept++
            ranges[kept] = user ":" f[2] ":" f[3]
            if (!mapped(f[2] + 0, f[2] + f[3] - 1)) inside = 0
        }
        if (kept > 0 && inside) {
            for (i = 1; i <= kept; i++) print ranges[i]
            exit 0
        }
        for (i = 1; i <= n; i++) {
            start = lo[i] < 1 ? 1 : lo[i]
            end = hi[i] > 65535 ? 65535 : hi[i]
            if (start > end) continue
            if (id >= start && id <= end) {
                emit(start, id - 1)
                emit(id + 1, end)
            } else {
                emit(start, end)
            }
        }
    }
'
