#!/usr/bin/env bash
# Runs inside the Arch ISO (via the archiso `script=` boot parameter) and
# produces a "freshly pacstrapped" system on /dev/vda — the starting point
# archsetup expects — then powers off.
#
# Kernel cmdline knobs (set by test/vm.sh):
#   archsetup.host=<http://10.0.2.2:PORT>   where this script + ssh key are served
#   archsetup.boot=systemd-boot|grub        bootloader to pre-install
#   archsetup.mirror=<Server URL>           pacman mirror to use
set -euxo pipefail
exec > >(tee /dev/ttyS0) 2>&1

arg() { sed -n "s/.*\barchsetup\.$1=\([^ ]*\).*/\1/p" /proc/cmdline; }
HOST=$(arg host) BOOT=$(arg boot) MIRROR=$(arg mirror)
BOOT=${BOOT:-systemd-boot}
DISK=/dev/vda

# the ISO starts reflector on boot; we want a known mirror instead
systemctl stop reflector.service 2>/dev/null || true
[[ -n $MIRROR ]] && echo "Server = $MIRROR" > /etc/pacman.d/mirrorlist
timedatectl set-ntp true

# ---- partitions: 1G ESP on /boot + btrfs with archinstall-style subvolumes ----
sgdisk -Z "$DISK"
sgdisk -n1:0:+1G -t1:ef00 -c1:ESP -n2:0:0 -t2:8304 -c2:root "$DISK"
partprobe "$DISK"; sleep 1
mkfs.fat -F32 -n ESP "${DISK}1"
mkfs.btrfs -f -L arch "${DISK}2"

mount "${DISK}2" /mnt
for sv in @ @home @log @pkg @snapshots; do btrfs subvolume create "/mnt/$sv"; done
umount /mnt
opts=noatime,compress=zstd
mount -o "$opts,subvol=@" "${DISK}2" /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,.snapshots}
mount -o "$opts,subvol=@home"      "${DISK}2" /mnt/home
mount -o "$opts,subvol=@log"       "${DISK}2" /mnt/var/log
mount -o "$opts,subvol=@pkg"       "${DISK}2" /mnt/var/cache/pacman/pkg
mount -o "$opts,subvol=@snapshots" "${DISK}2" /mnt/.snapshots
mount "${DISK}1" /mnt/boot

# ---- base system (deliberately minimal: no network manager, no sudo) ---------
pkgs=(base linux linux-firmware btrfs-progs openssh vim)
[[ $BOOT == grub ]] && pkgs+=(grub efibootmgr)
pacstrap -K /mnt "${pkgs[@]}"
genfstab -U /mnt >> /mnt/etc/fstab

# ---- just enough config to reach it over ssh ---------------------------------
mkdir -p /mnt/root/.ssh
curl -fsS "$HOST/id_ed25519.pub" > /mnt/root/.ssh/authorized_keys
chmod 700 /mnt/root/.ssh; chmod 600 /mnt/root/.ssh/authorized_keys

cat > /mnt/etc/systemd/network/20-wired.network <<'EOF'
[Match]
Name=en*

[Network]
DHCP=yes
EOF

arch-chroot /mnt bash -euxc '
    echo "root:root" | chpasswd
    systemctl enable sshd systemd-networkd systemd-resolved
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
'

# serial console so test/vm.sh can watch the boot
cmdline="root=UUID=$(blkid -s UUID -o value "${DISK}2") rootflags=subvol=@ rw console=tty0 console=ttyS0,115200"
case $BOOT in
    systemd-boot)
        arch-chroot /mnt bootctl install
        printf 'default arch.conf\ntimeout 2\n' > /mnt/boot/loader/loader.conf
        printf 'title Arch Linux\nlinux /vmlinuz-linux\ninitrd /initramfs-linux.img\noptions %s\n' "$cmdline" \
            > /mnt/boot/loader/entries/arch.conf
        ;;
    grub)
        sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"console=tty0 console=ttyS0,115200\"|" /mnt/etc/default/grub
        arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
        arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
        ;;
esac

sync
echo ARCHSETUP_PACSTRAP_DONE
systemctl poweroff
