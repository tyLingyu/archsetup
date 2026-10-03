#!/usr/bin/env bash
# Timezone, locale, hostname, root password, user + sudo, microcode, base tools.

# ---- timezone ----------------------------------------------------------------
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
run hwclock --systohc
run timedatectl set-ntp true || true
ok "Timezone: $TIMEZONE"

# ---- locale ------------------------------------------------------------------
for l in en_US.UTF-8 zh_CN.UTF-8 "$SYS_LANG"; do
    sed -i "s/^#\s*\(${l} UTF-8\)/\1/" /etc/locale.gen
done
run locale-gen
echo "LANG=$SYS_LANG" > /etc/locale.conf
ok "LANG=$SYS_LANG"

# ---- hostname ----------------------------------------------------------------
echo "$HOSTNAME_NEW" > /etc/hostname
hostnamectl hostname "$HOSTNAME_NEW" 2>/dev/null || true
if ! grep -q "$HOSTNAME_NEW" /etc/hosts; then
    cat >> /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME_NEW.localdomain $HOSTNAME_NEW
EOF
fi
ok "Hostname: $HOSTNAME_NEW"

# ---- root --------------------------------------------------------------------
if [[ -n $ROOT_HASH ]]; then
    usermod -p "$ROOT_HASH" root
    ok "Root password set."
fi

# ---- user + sudo -------------------------------------------------------------
pac sudo
if [[ -n $USER_NEW ]] && ! id "$USER_NAME" &>/dev/null; then
    run useradd -m -G wheel -s /bin/bash "$USER_NAME"
else
    run usermod -aG wheel "$USER_NAME"
fi
[[ -n $USER_HASH ]] && usermod -p "$USER_HASH" "$USER_NAME"

echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
visudo -cf /etc/sudoers.d/10-wheel >/dev/null
ok "User $USER_NAME (wheel, sudo)"

# the user's password is in place now: drop the hashes from disk
sed -i '/^ROOT_HASH=/d; /^USER_HASH=/d' "$ANSWERS_FILE"

# ---- microcode ---------------------------------------------------------------
case $(awk -F': ' '/^vendor_id/{print $2; exit}' /proc/cpuinfo) in
    GenuineIntel) pac intel-ucode ;;
    AuthenticAMD) pac amd-ucode ;;
esac

# ---- base tools --------------------------------------------------------------
pac man-db man-pages bash-completion pacman-contrib vim less wget unzip \
    openssh linux-firmware polkit
svc_enable fstrim.timer paccache.timer

# ---- per-user desktop language (systemd user environment, not the tty) -------
if [[ -n ${USER_LANG:-} ]]; then
    d=$(user_home)/.config/environment.d
    as_user mkdir -p "$d"
    printf 'LANG=%s\nLANGUAGE=zh_CN:en_US\n' "$USER_LANG" | as_user tee "$d/10-locale.conf" >/dev/null
    ok "Desktop session language: $USER_LANG"
fi
