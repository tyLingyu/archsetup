#!/usr/bin/env bash
# shellcheck disable=SC2034
# Optional application catalogue shown as checklists in the wizard.
#
# Format: category|packages|description|default
#   - packages: space separated; the FIRST one is the checklist tag
#   - default : on / off  (zh_on = on only when the UI language is Chinese)
#   - packages missing from the sync repos are built from AUR via paru
#
# Edit freely — categories need a "cat_<name>" string in lib/i18n.sh.

APP_CATEGORIES=(fonts input browser terminal cli dev media chat office gaming system)

APP_LIST='
fonts|noto-fonts noto-fonts-cjk noto-fonts-emoji|Noto Sans / CJK / Emoji|on
fonts|ttf-jetbrains-mono-nerd|JetBrains Mono Nerd Font|on
fonts|ttf-maplemono-nf-cn-unhinted|Maple Mono NF CN|zh_on

input|fcitx5-im fcitx5-chinese-addons|Fcitx5 + Chinese Pinyin|zh_on
input|fcitx5-rime rime-ice-git|Fcitx5 Rime + rime-ice|off
input|fcitx5-mozc|Fcitx5 Mozc (Japanese)|off

browser|firefox|Firefox|on
browser|chromium|Chromium|off
browser|google-chrome|Google Chrome (AUR)|off
browser|zen-browser-bin|Zen Browser (AUR)|off
browser|microsoft-edge-stable-bin|Microsoft Edge (AUR)|off

terminal|kitty|kitty|off
terminal|foot|foot|off
terminal|ghostty|Ghostty|off
terminal|alacritty|Alacritty|off

cli|fastfetch|fastfetch|on
cli|btop|btop|on
cli|fzf ripgrep fd bat eza zoxide|fzf ripgrep fd bat eza zoxide|on
cli|yazi|yazi file manager|off
cli|zsh|zsh|off
cli|fish|fish|off
cli|starship|starship prompt|off

dev|neovim|Neovim|on
dev|visual-studio-code-bin|VS Code (AUR)|off
dev|docker docker-compose docker-buildx|Docker|off

media|mpv|mpv|on
media|vlc|VLC|off
media|obs-studio|OBS Studio|off
media|gimp|GIMP|off
media|krita|Krita|off
media|kdenlive|Kdenlive|off

chat|linuxqq|QQ (AUR)|off
chat|wechat|WeChat (AUR)|off
chat|telegram-desktop|Telegram|off
chat|thunderbird|Thunderbird|off

office|libreoffice-fresh|LibreOffice|off
office|onlyoffice-bin|ONLYOFFICE|off
office|wps-office-cn|WPS Office CN (AUR)|off
office|obsidian|Obsidian|off
office|typora|Typora (AUR)|off

gaming|steam|Steam (multilib)|off
gaming|lutris|Lutris|off
gaming|mangohud|MangoHud|off

system|flatpak|Flatpak|off
system|gparted|GParted|off
system|localsend|LocalSend|off
system|qbittorrent|qBittorrent|off
system|flclash|FlClash|off
system|clash-verge-rev-bin|Clash Verge Rev (AUR)|off
system|snapper btrfs-assistant|Snapper + Btrfs Assistant (btrfs only)|off
system|timeshift|Timeshift|off
'

# apps_in CATEGORY -> "packages|description|on/off" lines
apps_in() {
    local c p d def
    while IFS='|' read -r c p d def; do
        [[ $c == "$1" ]] || continue
        [[ $def == zh_on ]] && { [[ ${UI_LANG:-en} == zh ]] && def=on || def=off; }
        printf '%s|%s|%s\n' "$p" "$d" "$def"
    done <<<"$APP_LIST"
}

# app_pkgs TAG -> full package list for a checklist tag
app_pkgs() {
    local c p d def
    while IFS='|' read -r c p d def; do
        [[ ${p%% *} == "$1" ]] && { echo "$p"; return; }
    done <<<"$APP_LIST"
    echo "$1"
}
