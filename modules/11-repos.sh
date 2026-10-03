#!/usr/bin/env bash
# pacman.conf tweaks, multilib, archlinuxcn, chaotic-aur, paru,
# and routing GitHub downloads in PKGBUILDs through the selected gh-proxy.

conf=/etc/pacman.conf
cp -f "$conf" "$conf.archsetup.bak"

# ---- pacman.conf niceties ----------------------------------------------------
sed -i 's/^#\s*Color$/Color/' "$conf"
sed -i 's/^#\?\s*ParallelDownloads.*/ParallelDownloads = 10/' "$conf"

# ---- multilib (steam, wine, 32-bit drivers) ----------------------------------
if ! grep -q '^\[multilib\]' "$conf"; then
    sed -i '/^#\s*\[multilib\]/,/^#\s*Include/ s/^#\s*//' "$conf"
    ok "Enabled [multilib]"
fi

# ---- archlinuxcn (always) ----------------------------------------------------
if ! grep -q '^\[archlinuxcn\]' "$conf"; then
    # several servers so pacman can fall back when one is flaky
    cn_servers=(
        'Server = https://mirrors.ustc.edu.cn/archlinuxcn/$arch'
        'Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/$arch'
    )
    official='Server = https://repo.archlinuxcn.org/$arch'
    {
        echo
        echo '[archlinuxcn]'
        if is_cn; then printf '%s\n' "${cn_servers[@]}" "$official"
        else printf '%s\n' "$official" "${cn_servers[@]}"; fi
    } >> "$conf"
    ok "Added [archlinuxcn]"
fi
# archlinuxcn-keyring is signed by farseerfc (an Arch packager, already in archlinux-keyring)
run pacman-key --lsign-key "farseerfc@archlinux.org"
run pacman -Sy --needed --noconfirm archlinuxcn-keyring

# ---- chaotic-aur (optional) --------------------------------------------------
if [[ $USE_CHAOTIC == yes ]] && ! grep -q '^\[chaotic-aur\]' "$conf"; then
    key=3056513887B78AEB
    got=0
    for ks in keyserver.ubuntu.com hkps://keys.openpgp.org; do
        run pacman-key --recv-key "$key" --keyserver "$ks" && { got=1; break; }
    done
    ((got)) || die "Could not fetch the chaotic-aur key."
    run pacman-key --lsign-key "$key"
    run pacman -U --noconfirm \
        'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
        'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
    printf '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' >> "$conf"
    ok "Added [chaotic-aur]"
fi

run pacman -Syu --noconfirm

# ---- AUR helper --------------------------------------------------------------
pac base-devel git paru

# ---- route GitHub through gh-proxy for makepkg -------------------------------
# Instead of editing every PKGBUILD:
#   * git sources   -> system-wide git url.<proxy>.insteadOf
#   * http sources  -> a DLAGENTS wrapper that prefixes GitHub URLs
if [[ -n $GH_PROXY ]]; then
    git config --system url."${GH_PROXY}https://github.com/".insteadOf "https://github.com/"

    cat > /usr/local/bin/archsetup-dlagent <<EOF
#!/bin/bash
# makepkg download agent: prefix GitHub URLs with ${GH_PROXY}  (installed by archsetup)
out=\$1 url=\$2
case \$url in
    https://github.com/*|https://raw.githubusercontent.com/*|https://codeload.github.com/*|\\
    https://objects.githubusercontent.com/*|https://gist.github.com/*|https://gist.githubusercontent.com/*)
        url="${GH_PROXY}\$url" ;;
esac
exec /usr/bin/curl -qgb "" -fLC - --retry 3 --retry-delay 3 -o "\$out" "\$url"
EOF
    chmod 755 /usr/local/bin/archsetup-dlagent

    mkdir -p /etc/makepkg.conf.d
    cat > /etc/makepkg.conf.d/archsetup-ghproxy.conf <<'EOF'
# installed by archsetup: GitHub downloads go through gh-proxy
DLAGENTS=('file::/usr/bin/curl -qgC - -o %o %u'
          'ftp::/usr/bin/curl -qgfC - --ftp-pasv --retry 3 --retry-delay 3 -o %o %u'
          'http::/usr/bin/curl -qgb "" -fLC - --retry 3 --retry-delay 3 -o %o %u'
          'https::/usr/local/bin/archsetup-dlagent %o %u'
          'rsync::/usr/bin/rsync --no-motd -z %u %o'
          'scp::/usr/bin/scp -C %u %o')
EOF
    ok "makepkg/git: GitHub -> ${GH_PROXY}"
fi
