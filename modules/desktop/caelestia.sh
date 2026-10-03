#!/usr/bin/env bash
# Caelestia on Hyprland via the official `caelestia install` (caelestia-cli).

pac hyprland kitty
pkg caelestia-cli
run as_user_bus caelestia install --noconfirm --aur-helper paru
