# blacklist

A curated IP blacklist (`blacklist.netset`) and a self-contained script to enforce it on Linux using **nftables**.

The list contains IPv4 addresses and CIDR subnets, one per line, in [netset format](https://github.com/firehol/blocklist-ipsets).

## Contents

| File | Description |
|------|-------------|
| `blacklist.netset` | IP/CIDR blacklist, one entry per line |
| `blacklist-update.sh` | Script that downloads the list and loads it into an nftables set |

## Requirements

- Linux with nftables (kernel ≥ 3.13, `nft` ≥ 0.9)
- `curl`
- root privileges

```bash
# Debian / Ubuntu
apt install nftables curl

# RHEL / CentOS / Fedora
dnf install nftables curl

# Arch Linux
pacman -S nftables curl
```

## Installation

No manual firewall configuration is needed. The script is idempotent: it creates the required nftables table, set, chains and rules on first run, and only refreshes the set afterwards.

```bash
install -m 755 blacklist-update.sh /usr/local/sbin/blacklist-update.sh
```

Schedule it with cron (daily update at 03:00, plus reload at boot since nftables sets do not survive a reboot):

```bash
cat > /etc/cron.d/blacklist << 'EOF'
0 3 * * * root /usr/local/sbin/blacklist-update.sh
@reboot root sleep 60 && /usr/local/sbin/blacklist-update.sh
EOF
```

Run it once manually to apply the blacklist immediately:

```bash
sudo /usr/local/sbin/blacklist-update.sh
```

## How it works

- Downloads `blacklist.netset` and keeps only valid IPv4/CIDR entries.
- Sanity check: aborts without touching the firewall if the downloaded file looks broken.
- Loads everything in a **single atomic nftables transaction** (`nft -f`): the rules either apply fully or not at all.
- Uses a dedicated `inet blacklist` table with hook priority `-10`, so it runs before standard filter chains and does not interfere with existing firewall configuration.
- The set uses `flags interval` with `auto-merge`: single IPs and subnets coexist, adjacent ranges are merged automatically, and lookups are O(log n) regardless of list size — suitable for hundreds of thousands of entries.
- Traffic from blacklisted sources is dropped on both `input` and `forward` hooks.

## Verify

```bash
# Show the ruleset
nft list table inet blacklist

# Count loaded entries
nft -j list set inet blacklist blocked | grep -o '"prefix"\|"elem"' | wc -l

# Test a specific address
nft get element inet blacklist blocked '{ 1.2.3.4 }'
```

## Uninstall

```bash
nft delete table inet blacklist
rm -f /etc/cron.d/blacklist /usr/local/sbin/blacklist-update.sh
```

## License

MIT
