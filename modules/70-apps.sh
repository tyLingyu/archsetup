#!/usr/bin/env bash
# Applications picked in the wizard. Installed one by one: a broken AUR
# package is recorded and skipped instead of failing the whole module.

FAILED_FILE=$STATE_DIR/failed-apps
: > "$FAILED_FILE"
home=$(user_home)

for tag in ${APPS:-}; do
    for p in $(app_pkgs "$tag"); do
        if pacman -Qq "$p" &>/dev/null; then continue; fi
        # groups (fcitx5-im) are not "in_repos" but pacman installs them fine
        if pacman -Sg "$p" &>/dev/null; then pac "$p" && continue; fi
        pkg "$p" || { warn "Failed: $p"; echo "$p" >> "$FAILED_FILE"; }
    done
done

installed() { pacman -Qq "$1" &>/dev/null; }

# ---- post-install tweaks for some apps ---------------------------------------
if installed docker; then
    svc_enable docker.socket
    usermod -aG docker "$USER_NAME"
fi

if installed fcitx5; then
    # X11/XWayland apps; Wayland-native toolkits use the text-input protocol
    grep -q '^XMODIFIERS=' /etc/environment || echo 'XMODIFIERS=@im=fcitx' >> /etc/environment

    im=keyboard-us
    installed fcitx5-chinese-addons && im=pinyin
    installed fcitx5-rime && im=rime
    if [[ ! -f $home/.config/fcitx5/profile ]]; then
        as_user mkdir -p "$home/.config/fcitx5"
        as_user tee "$home/.config/fcitx5/profile" >/dev/null <<EOF
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=$im

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=$im
Layout=

[GroupOrder]
0=Default
EOF
    fi
    if installed rime-ice-git; then
        as_user mkdir -p "$home/.local/share/fcitx5/rime"
        [[ -f $home/.local/share/fcitx5/rime/default.custom.yaml ]] ||
            printf 'patch:\n  __include: rime_ice_suggestion:/\n' |
            as_user tee "$home/.local/share/fcitx5/rime/default.custom.yaml" >/dev/null
    fi
fi

if [[ -s $FAILED_FILE ]]; then
    warn "Some packages failed: $(xargs < "$FAILED_FILE")"
else
    ok "All selected applications installed."
fi
