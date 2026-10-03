#!/usr/bin/env bash
# QEMU test bench for archsetup (runs on the host, no root needed).
#
#   test/vm.sh fetch                    download + verify the latest Arch ISO
#   test/vm.sh create [systemd-boot|grub]
#                                       pacstrap a fresh btrfs system into the disk
#                                       image (unattended, via archiso script=)
#   test/vm.sh save NAME | restore NAME reflink snapshot of disk + UEFI vars
#   test/vm.sh boot [--gui]             boot the disk (UEFI), ssh on localhost:2222
#   test/vm.sh ssh [cmd...]             ssh into the running VM as root
#   test/vm.sh deploy                   copy this working tree to /opt/archsetup
#   test/vm.sh run ANSWERS              deploy + run install.sh unattended with a
#                                       preseed file from test/answers/
#   test/vm.sh shot                     screenshot the VM display (test/.vm/shot.png)
#   test/vm.sh type TEXT | key KEY      send keystrokes (lowercase letters/digits, ret, tab...)
#   test/vm.sh stop                     power the VM off
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(dirname "$HERE")
VM=$HERE/.vm
DISK=$VM/disk.raw
VARS=$VM/OVMF_VARS.fd
ISO=$VM/archlinux-x86_64.iso
KEY=$VM/id_ed25519
SSH_PORT=${SSH_PORT:-2222}
HTTP_PORT=${HTTP_PORT:-8719}
OVMF_CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd
OVMF_VARS_TPL=/usr/share/edk2/x64/OVMF_VARS.4m.fd
MEM=${MEM:-6G} CPUS=${CPUS:-4} DISK_SIZE=${DISK_SIZE:-40G}

mkdir -p "$VM"

# first Server line of the host mirrorlist, e.g. https://mirror.x/archlinux/$repo/os/$arch
host_mirror() { sed -n 's/^Server *= *//p' /etc/pacman.d/mirrorlist | head -1; }

accel() {
    if [[ -w /dev/kvm ]]; then echo "-enable-kvm -cpu host"
    else echo "WARNING: /dev/kvm not available, using slow TCG emulation" >&2; echo "-cpu max"; fi
}

SSH_OPTS=(-i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5)
ssh_vm()  { ssh "${SSH_OPTS[@]}" -p "$SSH_PORT" root@localhost "$@"; }
ssh_tty() { ssh "${SSH_OPTS[@]}" -p "$SSH_PORT" -t root@localhost "$@"; }

wait_ssh() {
    echo "Waiting for ssh on :$SSH_PORT ..."
    for _ in $(seq 1 120); do ssh_vm true 2>/dev/null && { echo "VM is up."; return; }; sleep 3; done
    echo "VM did not come up, see $VM/serial.log" >&2; return 1
}

cmd_fetch() {
    local base; base=$(host_mirror); base=${base%%/\$repo*}/iso/latest
    echo "Downloading from $base"
    curl -fL -o "$VM/sha256sums.txt" "$base/sha256sums.txt"
    curl -fL -C - -o "$ISO" "$base/archlinux-x86_64.iso"
    (cd "$VM" && grep ' archlinux-x86_64.iso$' sha256sums.txt | sha256sum -c -)
}

cmd_create() {
    local boot=${1:-systemd-boot}
    [[ -f $ISO ]] || { echo "No ISO, run: $0 fetch" >&2; exit 1; }
    [[ -f $KEY ]] || ssh-keygen -q -t ed25519 -N '' -f "$KEY"

    rm -f "$DISK"; truncate -s "$DISK_SIZE" "$DISK"
    cp "$OVMF_VARS_TPL" "$VARS"

    # kernel + initramfs + archiso search uuid straight from the ISO
    # files extracted from the ISO are read-only
    local ex=$VM/iso; [[ -d $ex ]] && chmod -R u+w "$ex"; rm -rf "$ex"; mkdir -p "$ex"
    bsdtar -xf "$ISO" -C "$ex" arch/boot/x86_64/vmlinuz-linux arch/boot/x86_64/initramfs-linux.img 'loader/entries/*'
    local uuid; uuid=$(grep -ho 'archisosearchuuid=[^ ]*' "$ex"/loader/entries/*.conf | head -1)

    # serve the pacstrap script and the ssh public key to the guest (10.0.2.2)
    local www=$VM/www; rm -rf "$www"; mkdir -p "$www"
    cp "$HERE/vm-pacstrap.sh" "$www/"; cp "$KEY.pub" "$www/id_ed25519.pub"
    python3 -m http.server "$HTTP_PORT" -d "$www" -b 127.0.0.1 >/dev/null 2>&1 &
    local http_pid=$!
    trap "kill $http_pid 2>/dev/null" EXIT

    local host=http://10.0.2.2:$HTTP_PORT
    echo "Installing base system ($boot), log: $VM/create.log"
    # shellcheck disable=SC2046
    qemu-system-x86_64 $(accel) -machine q35 -smp "$CPUS" -m "$MEM" \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$VARS" \
        -drive file="$DISK",format=raw,if=virtio,cache=unsafe \
        -cdrom "$ISO" \
        -kernel "$ex/arch/boot/x86_64/vmlinuz-linux" -initrd "$ex/arch/boot/x86_64/initramfs-linux.img" \
        -append "archisobasedir=arch $uuid console=tty0 console=ttyS0,115200 script=$host/vm-pacstrap.sh archsetup.host=$host archsetup.boot=$boot archsetup.mirror=$(host_mirror)" \
        -nic user,model=virtio-net-pci \
        -display none -monitor none -serial stdio | tee "$VM/create.log"

    grep -q ARCHSETUP_PACSTRAP_DONE "$VM/create.log" || { echo "pacstrap failed, see $VM/create.log" >&2; exit 1; }
    echo "Base system ready. Tip: $0 save fresh-$boot"
}

cmd_save()    { cp --reflink=auto "$DISK" "$VM/$1.raw"; cp "$VARS" "$VM/$1.vars"; echo "Saved $1"; }
cmd_restore() { cp --reflink=auto "$VM/$1.raw" "$DISK"; cp "$VM/$1.vars" "$VARS"; echo "Restored $1"; }

cmd_boot() {
    # a VGA device even when headless, so `test/vm.sh shot` can screendump
    local display=(-display none -vga std)
    [[ ${1:-} == --gui ]] && display=(-vga std -display gtk)
    # shellcheck disable=SC2046
    qemu-system-x86_64 $(accel) -machine q35 -smp "$CPUS" -m "$MEM" \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$VARS" \
        -drive file="$DISK",format=raw,if=virtio,cache=unsafe \
        -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:"$SSH_PORT"-:22 \
        "${display[@]}" -serial file:"$VM/serial.log" \
        -monitor unix:"$VM/monitor.sock",server,nowait \
        -daemonize -pidfile "$VM/qemu.pid"
    wait_ssh
}

cmd_stop() {
    ssh_vm systemctl poweroff 2>/dev/null || true
    for _ in $(seq 1 30); do [[ -e /proc/$(cat "$VM/qemu.pid" 2>/dev/null || echo 0) ]] || { echo stopped; return; }; sleep 1; done
    echo quit | socat - UNIX-CONNECT:"$VM/monitor.sock" >/dev/null || true
}

# screenshot of the VM display -> test/.vm/shot.png
cmd_shot() {
    echo "screendump $VM/shot.ppm" | socat - UNIX-CONNECT:"$VM/monitor.sock" >/dev/null
    sleep 1
    python3 - "$VM/shot.ppm" "$VM/shot.png" <<'PY' 2>/dev/null || magick "$VM/shot.ppm" "$VM/shot.png"
import sys, zlib, struct
d = open(sys.argv[1], 'rb').read().split(b'\n', 3)
w, h = map(int, d[1].split()); px = d[3]
raw = b''.join(b'\0' + px[y*w*3:(y+1)*w*3] for y in range(h))
c = lambda t, b: struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t + b))
open(sys.argv[2], 'wb').write(b'\x89PNG\r\n\x1a\n' + c(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + c(b'IDAT', zlib.compress(raw)) + c(b'IEND', b''))
PY
    echo "$VM/shot.png"
}

# type text / press keys on the VM console, e.g. `test/vm.sh key ret`
cmd_type() { local ch; for ((i = 0; i < ${#1}; i++)); do ch=${1:i:1}; echo "sendkey $ch" | socat - UNIX-CONNECT:"$VM/monitor.sock" >/dev/null; done; }
cmd_key()  { echo "sendkey $1" | socat - UNIX-CONNECT:"$VM/monitor.sock" >/dev/null; }

cmd_deploy() {
    tar -C "$REPO" --exclude=.git --exclude=test/.vm -cf - . | ssh_vm 'rm -rf /opt/archsetup && mkdir -p /opt/archsetup && tar -C /opt/archsetup -xf -'
    ssh_vm 'mkdir -p /var/lib/archsetup && [[ -f /var/lib/archsetup/bootstrap.conf ]] ||
            printf "UI_LANG=en\nGH_PROXY=\nREPO_DIR=/opt/archsetup\n" > /var/lib/archsetup/bootstrap.conf'
    echo "Deployed working tree to /opt/archsetup"
}

cmd_run() {
    local answers=$HERE/answers/${1:?answers file name, see test/answers/}
    [[ -f $answers ]] || answers=$1
    cmd_deploy
    ssh_vm 'pacman -Sy --needed --noconfirm dialog git >/dev/null'
    scp "${SSH_OPTS[@]}" -P "$SSH_PORT" "$answers" root@localhost:/root/answers.conf
    ssh_tty 'ARCHSETUP_ANSWERS=/root/answers.conf bash /opt/archsetup/install.sh'
}

case ${1:-} in
    fetch|create|save|restore|boot|stop|deploy|run|shot|type|key) c=$1; shift; "cmd_$c" "$@" ;;
    ssh) shift; ssh_vm "$@" ;;
    *) sed -n '2,15p' "$0"; exit 1 ;;
esac
