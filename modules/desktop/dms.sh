#!/usr/bin/env bash
# DankMaterialShell on niri or Hyprland, using DMS's own default configs.

wm_base
pac "dms-shell-$COMPOSITOR"

# deploys the compositor + kitty configs (not the autostart, see below)
run as_user_bus dms setup headless --compositor "$COMPOSITOR" --terminal kitty --skip-existing

# headless setup only deploys configs; start DMS with the session
case $COMPOSITOR in
    niri)
        # niri.service pulls in graphical-session.target, which wants dms.service
        run as_user_bus systemctl --user enable dms.service
        ;;
    hyprland)
        # start-hyprland doesn't activate graphical-session.target
        cfg=$(user_home)/.config/hypr/hyprland.lua
        if [[ -f $cfg ]] && ! grep -q 'dms run' "$cfg"; then
            printf '\n-- start DankMaterialShell (added by archsetup)\nhl.on("hyprland.start", function()\n  hl.exec_cmd("dms run")\nend)\n' >> "$cfg"
        fi
        ;;
esac
