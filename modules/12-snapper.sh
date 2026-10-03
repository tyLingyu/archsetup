#!/usr/bin/env bash
# btrfs root: set up snapper for / and import the raw pre-install snapshot.

PRESNAP=/.archsetup-presnap

is_btrfs_root || return 0

pac snapper btrfs-progs

if ! snapper list-configs 2>/dev/null | awk '{print $1}' | grep -qx root; then
    if mountpoint -q /.snapshots; then
        # a dedicated @snapshots subvolume is mounted (archinstall layout):
        # snapper refuses an existing /.snapshots, so swap it out and back in
        run umount /.snapshots
        rmdir /.snapshots
        run snapper -c root create-config /
        run btrfs subvolume delete /.snapshots
        mkdir /.snapshots
        run mount /.snapshots
    else
        [[ -d /.snapshots ]] && rmdir /.snapshots 2>/dev/null
        run snapper -c root create-config /
    fi
    chmod 750 /.snapshots
fi

# snap-pac (installed in 99-finish) covers pacman; keep a modest history
run snapper -c root set-config TIMELINE_CREATE=no NUMBER_LIMIT=15 NUMBER_LIMIT_IMPORTANT=5
ok "snapper config 'root' ready."

# ---- import the raw snapshot from 00-presnap in snapper's on-disk format -----
if [[ -d $PRESNAP ]]; then
    last=$(find /.snapshots -mindepth 1 -maxdepth 1 -regex '.*/[0-9]+' -printf '%f\n' | sort -n | tail -1)
    n=$(( ${last:-0} + 1 ))
    mkdir -p "/.snapshots/$n"
    run btrfs subvolume snapshot -r "$PRESNAP" "/.snapshots/$n/snapshot"
    cat > "/.snapshots/$n/info.xml" <<EOF
<?xml version="1.0"?>
<snapshot>
  <type>single</type>
  <num>$n</num>
  <date>$(cat "$STATE_DIR/presnap.date" 2>/dev/null || date -u '+%F %T')</date>
  <description>archsetup: before first package</description>
</snapshot>
EOF
    run btrfs subvolume delete "$PRESNAP"
    # snapperd caches the snapshot list
    systemctl try-restart snapperd.service 2>/dev/null || true
    ok "Imported pre-install snapshot as #$n."
fi

run snapper -c root list
