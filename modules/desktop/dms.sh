#!/usr/bin/env bash
# DankMaterialShell on niri or Hyprland, using DMS's own default configs.

wm_base
pac "dms-shell-$COMPOSITOR"

# deploys compositor + kitty configs and wires dms.service into the session;
# needs the user's systemd instance, hence as_user_bus
run as_user_bus dms setup headless --compositor "$COMPOSITOR" --terminal kitty --skip-existing
