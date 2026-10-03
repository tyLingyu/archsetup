#!/usr/bin/env bash
# Install / keep the bootloader, add Windows if present, snapshot boot on btrfs,
# and optionally remove the bootloaders that were there before.

CMDLINE=$(boot_cmdline)
ESP=$(esp_path 2>/dev/null || true)
is_uefi && pac efibootmgr
is_uefi && [[ -z $ESP ]] && die "UEFI system but no mounted ESP (vfat on /efi, /boot or /boot/efi)."

info "ESP: ${ESP:-none (BIOS)}"
info "cmdline: $CMDLINE"

# kernels installed from packages: linux, linux-zen, linux-lts, ...
mapfile -t KERNELS < <(cat /usr/lib/modules/*/pkgbase 2>/dev/null | sort -u)
((${#KERNELS[@]})) || die "No kernel found in /usr/lib/modules."
info "kernels: ${KERNELS[*]}"

WIN_ESP=$(is_uefi && find_windows_esp || true)
[[ -n $WIN_ESP ]] && info "Windows Boot Manager found on $WIN_ESP"

# ---- early microcode via mkinitcpio (so no bootloader needs ucode initrds) ----
if [[ -f /etc/mkinitcpio.conf ]] && ! grep -Eq '^HOOKS=.*\bmicrocode\b' /etc/mkinitcpio.conf; then
    sed -i -E '/^HOOKS=/ s/\bautodetect\b/autodetect microcode/' /etc/mkinitcpio.conf
    grep -Eq '^HOOKS=.*\bmicrocode\b' /etc/mkinitcpio.conf && ok "Added microcode hook to mkinitcpio."
fi

# ---- helpers -----------------------------------------------------------------
efi_delete_label() {   # remove UEFI NVRAM entries whose label matches (case-insensitive)
    local num
    for num in $(efibootmgr | awk -v l="$1" 'BEGIN{IGNORECASE=1} /^Boot[0-9A-F]{4}/ && index(tolower($0), tolower(l)) {print substr($1,5,4)}'); do
        run efibootmgr -q -b "$num" -B
    done
}

# Windows on another ESP: copy its loader to ours so every bootloader can see it
copy_windows_to_esp() {
    [[ -n $WIN_ESP && $WIN_ESP != "$ESP" ]] || return 0
    [[ -d $ESP/EFI/Microsoft ]] && return 0
    local need free
    need=$(du -sk "$WIN_ESP/EFI/Microsoft" | cut -f1)
    free=$(df -k --output=avail "$ESP" | tail -1)
    if ((free > need + 10240)); then
        run cp -r "$WIN_ESP/EFI/Microsoft" "$ESP/EFI/"
        ok "Copied Windows Boot Manager to $ESP"
    else
        warn "Not enough space on $ESP to copy Windows Boot Manager (${need}K needed)."
        return 1
    fi
}

root_disk() {   # whole disk under / (through LUKS/LVM), for BIOS grub-install
    local src; src=$(findmnt -no SOURCE / | sed 's/\[.*//')
    lsblk -npso NAME,TYPE "$src" | awk '$2=="disk"{print $1; exit}'
}

# ==============================================================================
install_systemd_boot() {
    run bootctl install --esp-path="$ESP"
    cat > "$ESP/loader/loader.conf" <<'EOF'
default @saved
timeout 3
console-mode max
editor no
EOF
    if [[ $ESP == /boot ]]; then
        # kernels already live on the ESP: plain entries
        local k
        for k in "${KERNELS[@]}"; do
            cat > "$ESP/loader/entries/arch-$k.conf" <<EOF
title   Arch Linux ($k)
linux   /vmlinuz-$k
initrd  /initramfs-$k.img
options $CMDLINE
EOF
            cat > "$ESP/loader/entries/arch-$k-fallback.conf" <<EOF
title   Arch Linux ($k, fallback)
linux   /vmlinuz-$k
initrd  /initramfs-$k-fallback.img
options $CMDLINE
EOF
        done
    else
        # ESP is not /boot: build UKIs straight onto the ESP, sd-boot finds them
        echo "$CMDLINE" > /etc/kernel/cmdline
        mkdir -p "$ESP/EFI/Linux"
        local preset
        for k in "${KERNELS[@]}"; do
            preset=/etc/mkinitcpio.d/$k.preset
            [[ -f $preset ]] || continue
            sed -i -E "s|^#?default_uki=.*|default_uki=\"$ESP/EFI/Linux/arch-$k.efi\"|;
                       s|^#?fallback_uki=.*|fallback_uki=\"$ESP/EFI/Linux/arch-$k-fallback.efi\"|" "$preset"
        done
        run mkinitcpio -P
    fi
    copy_windows_to_esp || true      # sd-boot auto-detects EFI/Microsoft on its ESP
    svc_enable systemd-boot-update.service
}

install_grub() {
    local pkgs=(grub)
    is_uefi && pkgs+=(efibootmgr)
    [[ -n $WIN_ESP ]] && pkgs+=(os-prober)
    pac "${pkgs[@]}"

    if is_uefi; then
        run grub-install --target=x86_64-efi --efi-directory="$ESP" --bootloader-id=GRUB
    else
        local disk; disk=$(root_disk)
        [[ -n $disk ]] || die "Cannot determine the disk for BIOS grub-install."
        run grub-install --target=i386-pc "$disk"
    fi

    # grub-mkconfig adds root=/rootflags=/rw itself; keep everything else
    local a extra=()
    for a in $CMDLINE; do
        case $a in root=*|rootflags=*|rw|ro|quiet|loglevel=*) ;; *) extra+=("$a") ;; esac
    done
    local def=/etc/default/grub
    sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${extra[*]}\"|" "$def"
    if [[ -n $WIN_ESP ]]; then
        sed -i 's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' "$def"
        grep -q '^GRUB_DISABLE_OS_PROBER=' "$def" || echo 'GRUB_DISABLE_OS_PROBER=false' >> "$def"
    fi
    # /boot inside LUKS
    if lsblk -nso TYPE "$(findmnt -no SOURCE /boot 2>/dev/null || findmnt -no SOURCE / | sed 's/\[.*//')" | grep -qx crypt; then
        sed -i 's/^#\?GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=y/' "$def"
    fi

    if is_btrfs_root; then
        pac grub-btrfs inotify-tools
        svc_enable grub-btrfsd.service
    fi
    run grub-mkconfig -o /boot/grub/grub.cfg
}

install_limine() {
    echo "$CMDLINE" > /etc/kernel/cmdline
    mkdir -p /etc/default
    if [[ -f /etc/default/limine ]] && grep -q '^ESP_PATH=' /etc/default/limine; then
        sed -i "s|^ESP_PATH=.*|ESP_PATH=\"$ESP\"|" /etc/default/limine
    else
        echo "ESP_PATH=\"$ESP\"" >> /etc/default/limine
    fi

    pac limine efibootmgr
    pkg limine-mkinitcpio-hook        # chaotic-aur / AUR
    run limine-install
    run limine-update

    if [[ -n $WIN_ESP ]] && copy_windows_to_esp; then
        run limine-entry-tool --add-efi "Windows Boot Manager" "$ESP/EFI/Microsoft/Boot/bootmgfw.efi" --overwrite --quiet
    fi
    if is_btrfs_root; then
        pkg limine-snapper-sync
        svc_enable limine-snapper-sync.service
    fi
}

install_refind() {
    pac refind efibootmgr
    run refind-install
    cat > /boot/refind_linux.conf <<EOF
"Boot with standard options"  "$CMDLINE"
"Boot to terminal"            "$CMDLINE systemd.unit=multi-user.target"
EOF
    # kernels sit inside a btrfs subvolume when /boot isn't its own partition
    local conf=$ESP/EFI/refind/refind.conf subvol
    if is_btrfs_root && [[ $(findmnt -no TARGET /boot) != /boot ]]; then
        subvol=$(findmnt -no FSROOT / | sed 's|^/||')
        grep -q "^also_scan_dirs.*$subvol/boot" "$conf" || echo "also_scan_dirs +,$subvol/boot" >> "$conf"
    fi
    # rEFInd scans every ESP for Windows by itself
}

# ==============================================================================
remove_old() {
    local old
    for old in $BOOT_OLD; do
        [[ $old == "$BOOTLOADER" ]] && continue
        info "Removing old bootloader: $old"
        case $old in
            systemd-boot)
                run bootctl remove || true
                rm -rf "$ESP/loader"
                ;;
            grub)
                local d
                for d in "$ESP"/EFI/*/grubx64.efi; do [[ -f $d ]] && run rm -rf "$(dirname "$d")"; done
                is_uefi && efi_delete_label grub
                rm -rf /boot/grub
                run pacman -Rns --noconfirm grub grub-btrfs os-prober 2>/dev/null || true
                ;;
            limine)
                rm -rf "$ESP/EFI/limine" "$ESP/limine.conf"
                efi_delete_label limine
                run pacman -Rns --noconfirm limine-snapper-sync limine-mkinitcpio-hook limine 2>/dev/null || true
                ;;
            refind)
                rm -rf "$ESP/EFI/refind" /boot/refind_linux.conf
                efi_delete_label refind
                run pacman -Rns --noconfirm refind 2>/dev/null || true
                ;;
        esac
        ok "Removed $old"
    done
}

case $BOOTLOADER in
    keep)
        ok "Keeping: $BOOT_OLD"
        # only refresh what is safe to refresh
        if [[ " $BOOT_OLD " == *" grub "* && -f /boot/grub/grub.cfg ]]; then
            [[ -n $WIN_ESP ]] && pac os-prober && sed -i 's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
            is_btrfs_root && pac grub-btrfs inotify-tools && svc_enable grub-btrfsd.service
            run grub-mkconfig -o /boot/grub/grub.cfg
        fi
        ;;
    systemd-boot) install_systemd_boot ;;
    grub)         install_grub ;;
    limine)       install_limine ;;
    refind)       install_refind ;;
esac

if [[ $BOOTLOADER != keep && -n ${BOOT_REMOVE_OLD:-} ]]; then
    remove_old
fi

# removing the old loader may have taken EFI/BOOT/BOOTX64.EFI with it; keep a
# fallback so the disk still boots after the firmware forgets its NVRAM entries
if is_uefi && [[ ! -f $ESP/EFI/BOOT/BOOTX64.EFI ]]; then
    case $BOOTLOADER in
        systemd-boot) run bootctl install --esp-path="$ESP" --no-variables ;;
        grub)         run grub-install --target=x86_64-efi --efi-directory="$ESP" --removable ;;
        limine)       run limine-install --fallback ;;
        refind)       mkdir -p "$ESP/EFI/BOOT"; cp "$ESP/EFI/refind/refind_x64.efi" "$ESP/EFI/BOOT/BOOTX64.EFI" ;;
    esac
fi

is_uefi && run efibootmgr

# other ESPs mounted read-only by find_windows_esp
for m in /run/archsetup/esp-*; do mountpoint -q "$m" && umount "$m"; done
true
