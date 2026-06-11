#!/usr/bin/env bash
# blacklist-update.sh — populate an nftables set from a remote IP blacklist.
# Self-contained and idempotent: creates the required nftables structure
# if missing, then atomically reloads the set. No manual setup needed.
#
# Cron: 0 3 * * * root /usr/local/sbin/blacklist-update.sh

set -euo pipefail

URL="https://raw.githubusercontent.com/ostap-mykhaylyak/blacklist/main/blacklist.netset"

TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT

curl -fsSL --retry 3 "$URL" \
  | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?$' \
  | sort -u > "$TMP"

# Abort if the download looks broken; never flush the set with bad data
[[ $(wc -l < "$TMP") -ge 100 ]] || { echo "blacklist: invalid file, skipping" >&2; exit 1; }

# Create structure if missing, then reload set and rules atomically
nft -f - << EOF
table inet blacklist {
    set blocked {
        type ipv4_addr
        flags interval
        auto-merge
    }
    chain input {
        type filter hook input priority -10; policy accept;
    }
    chain forward {
        type filter hook forward priority -10; policy accept;
    }
}
flush set inet blacklist blocked
flush chain inet blacklist input
flush chain inet blacklist forward
add rule inet blacklist input ip saddr @blocked drop
add rule inet blacklist forward ip saddr @blocked drop
add element inet blacklist blocked { $(paste -sd, "$TMP") }
EOF
