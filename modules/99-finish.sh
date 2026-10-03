#!/usr/bin/env bash
# Final touches, cleanup and the reboot prompt.

# ---- snapshots from now on: one pre/post pair per pacman transaction ---------
if is_btrfs_root && command -v snapper &>/dev/null; then
    pac snap-pac
    run snapper -c root set-config "ALLOW_USERS=$USER_NAME" SYNC_ACL=yes
fi

# ---- undo temporary state ----------------------------------------------------
if [[ -f $STATE_DIR/linger-enabled ]]; then
    loginctl disable-linger "$USER_NAME" || true
    rm -f "$STATE_DIR/linger-enabled"
fi
rm -f "$TMP_SUDOERS"
cp -f "$LOG_FILE" "$(user_home)/archsetup.log" && chown "$USER_NAME:" "$(user_home)/archsetup.log"

ok "archsetup finished."
