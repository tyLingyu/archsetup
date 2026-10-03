#!/usr/bin/env bash
# btrfs root: take a raw read-only snapshot of / BEFORE any package is
# installed. snapper isn't installed yet, so 12-snapper imports it later.

PRESNAP=/.archsetup-presnap

is_btrfs_root || { ok "Root is not btrfs, no snapshots."; return 0; }
command -v btrfs &>/dev/null || { warn "btrfs-progs missing, cannot snapshot before the first package."; return 0; }
[[ -e $PRESNAP ]] && { ok "Pre-install snapshot already exists."; return 0; }

run btrfs subvolume snapshot / "$PRESNAP"
# the wizard's answers (with password hashes) must not live on in the snapshot
rm -f "$PRESNAP$STATE_DIR/answers.conf" "$PRESNAP$STATE_DIR/progress"
run btrfs property set -ts "$PRESNAP" ro true
date -u '+%F %T' > "$STATE_DIR/presnap.date"
ok "Snapshot of / taken before installing anything."
