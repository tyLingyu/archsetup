#!/usr/bin/env bash
# btrfs root: snapshot right before the desktop is installed.

is_btrfs_root || return 0
command -v snapper &>/dev/null || { warn "snapper not set up, skipping."; return 0; }

# no cleanup algorithm: milestone snapshots are kept until removed by hand
run snapper -c root create \
    --description "archsetup: before desktop (${DESKTOP}${COMPOSITOR:+ + $COMPOSITOR})"
ok "Snapshot taken before installing the desktop."
