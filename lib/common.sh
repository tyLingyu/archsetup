#!/usr/bin/env bash
# shellcheck disable=SC2034
# Shared helpers for install.sh and modules/*.sh

STATE_DIR=/var/lib/archsetup
CONF_FILE=$STATE_DIR/bootstrap.conf     # written by bootstrap.sh
ANSWERS_FILE=$STATE_DIR/answers.conf    # written by the wizard
PROGRESS_FILE=$STATE_DIR/progress       # one finished module per line
LOG_FILE=/var/log/archsetup.log

R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' B=$'\e[34m' C=$'\e[36m' D=$'\e[2m' BOLD=$'\e[1m' N=$'\e[0m'

# ------------------------------------------------------------------------------
# logging
# ------------------------------------------------------------------------------
_log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"; }

info()    { printf '%s==>%s %s\n' "$B" "$N" "$*"; _log "INFO  $*"; }
ok()      { printf '%s  ✓%s %s\n' "$G" "$N" "$*"; _log "OK    $*"; }
warn()    { printf '%s  !%s %s\n' "$Y" "$N" "$*"; _log "WARN  $*"; }
err()     { printf '%s  ✗%s %s\n' "$R" "$N" "$*" >&2; _log "ERROR $*"; }
die()     { err "$*"; exit 1; }
section() { printf '\n%s%s━━━ %s ━━━%s\n' "$BOLD" "$C" "$*" "$N"; _log "===== $*"; }

# echo + run a command, mirroring its output into the log
run() {
    printf '%s  $ %s%s\n' "$D" "$*" "$N"
    _log "RUN   $*"
    "$@" 2>&1 | tee -a "$LOG_FILE"
    return "${PIPESTATUS[0]}"
}

# ------------------------------------------------------------------------------
# i18n: t KEY [printf args...]
# ------------------------------------------------------------------------------
declare -gA L_en=() L_zh=()

t() {
    local k=$1 v; shift
    if [[ ${UI_LANG:-en} == zh ]]; then v=${L_zh[$k]:-${L_en[$k]:-$k}}; else v=${L_en[$k]:-$k}; fi
    # shellcheck disable=SC2059
    printf "$v" "$@"
}

# ------------------------------------------------------------------------------
# dialog wrappers — all print the result on stdout; non-zero = Cancel/Back/Esc
# ------------------------------------------------------------------------------
_dlg() {
    dialog --stdout --colors --cr-wrap \
        --backtitle "$(t backtitle)" \
        --ok-label "$(t ok)" --cancel-label "$(t back)" \
        --yes-label "$(t yes)" --no-label "$(t no)" \
        "$@"
}

d_msg()    { _dlg --title "$1" --msgbox "$2" 0 0; }
d_info()   { _dlg --title "$1" --infobox "$2" 0 0; }
d_yesno()  { _dlg --title "$1" --yesno "$2" 0 0; }
d_noyes()  { _dlg --title "$1" --defaultno --yesno "$2" 0 0; }
d_input()  { _dlg --title "$1" --inputbox "$2" 0 0 "${3:-}"; }
d_pass()   { _dlg --title "$1" --insecure --passwordbox "$2" 0 0; }
# d_menu TITLE TEXT DEFAULT tag item [tag item...]
d_menu()   { local ti=$1 tx=$2 de=$3; shift 3; _dlg --title "$ti" --default-item "$de" --menu "$tx" 0 0 0 "$@"; }
# d_check TITLE TEXT tag item on|off [...]   -> one tag per line
d_check()  { local ti=$1 tx=$2; shift 2; _dlg --title "$ti" --separate-output --checklist "$tx" 0 0 0 "$@"; }

# ask for a password twice; prints a SHA-512 crypt hash (never the plaintext)
d_newpass() {
    local title=$1 p1 p2
    while :; do
        p1=$(d_pass "$title" "$(t pass_enter)") || return 1
        [[ -z $p1 ]] && { d_msg "$title" "$(t pass_empty)"; continue; }
        p2=$(d_pass "$title" "$(t pass_again)") || return 1
        [[ $p1 == "$p2" ]] && break
        d_msg "$title" "$(t pass_mismatch)"
    done
    printf '%s' "$p1" | openssl passwd -6 -stdin
}

# ------------------------------------------------------------------------------
# answers / progress
# ------------------------------------------------------------------------------
save_answer() {   # save_answer KEY VALUE   (also sets it in the current shell)
    local k=$1 v=$2
    printf -v "$k" '%s' "$v"
    touch "$ANSWERS_FILE"; chmod 600 "$ANSWERS_FILE"
    sed -i "/^${k}=/d" "$ANSWERS_FILE"
    printf '%s=%q\n' "$k" "$v" >> "$ANSWERS_FILE"
}
load_answers() { [[ -f $ANSWERS_FILE ]] && source "$ANSWERS_FILE"; return 0; }

is_done()   { grep -qxF "$1" "$PROGRESS_FILE" 2>/dev/null; }
mark_done() { is_done "$1" || echo "$1" >> "$PROGRESS_FILE"; }

# ------------------------------------------------------------------------------
# packages
# ------------------------------------------------------------------------------
in_repos() { pacman -Si -- "$1" &>/dev/null; }

pac() { run pacman -S --needed --noconfirm "$@"; }

TMP_SUDOERS=/etc/sudoers.d/99-archsetup-tmp

# run as the target user; paru needs passwordless sudo while unattended
as_user() {
    if [[ ! -f $TMP_SUDOERS ]]; then
        echo "$USER_NAME ALL=(ALL:ALL) NOPASSWD: ALL" > "$TMP_SUDOERS"
        chmod 440 "$TMP_SUDOERS"
    fi
    sudo -u "$USER_NAME" -H -- "$@"
}

# Install packages: from sync repos (core/extra/archlinuxcn/chaotic-aur) when
# available, otherwise build from AUR with paru as the target user.
pkg() {
    local p repo=() build=()
    for p in "$@"; do
        if in_repos "$p"; then repo+=("$p"); else build+=("$p"); fi
    done
    if ((${#repo[@]})); then pac "${repo[@]}" || return; fi
    if ((${#build[@]})); then
        command -v paru &>/dev/null || { err "paru missing, cannot build: ${build[*]}"; return 1; }
        run as_user paru -S --needed --noconfirm --skipreview "${build[@]}"
    fi
}

svc_enable() { run systemctl enable "$@"; }

# ------------------------------------------------------------------------------
# misc detection
# ------------------------------------------------------------------------------
is_uefi() { [[ -d /sys/firmware/efi/efivars ]]; }

esp_path() {
    local p
    p=$(bootctl --print-esp-path 2>/dev/null) && { echo "$p"; return; }
    for p in /efi /boot /boot/efi; do
        [[ $(findmnt -no FSTYPE "$p" 2>/dev/null) == vfat ]] && { echo "$p"; return; }
    done
    return 1
}

# China detection: timezone first, then GeoIP
is_cn() {
    [[ $(readlink -f /etc/localtime 2>/dev/null) == */Asia/Shanghai ]] && return 0
    [[ $(curl -fsS --max-time 3 https://ipinfo.io/country 2>/dev/null | tr -d '\r\n') == CN ]]
}

is_btrfs_root() { [[ $(findmnt -no FSTYPE /) == btrfs ]]; }

# Kernel command line for new boot entries: reuse what the running system
# booted with (already correct for LUKS / LVM / btrfs subvolumes), minus
# bootloader-specific arguments.
boot_cmdline() {
    local a out=()
    for a in $(</proc/cmdline); do
        case $a in BOOT_IMAGE=*|initrd=*|*.efi|*.EFI) continue ;; esac
        out+=("$a")
    done
    if [[ " ${out[*]} " != *" root="* ]]; then
        local extra=(root=UUID=$(findmnt -no UUID /) rw)
        is_btrfs_root && extra+=("rootflags=subvol=$(findmnt -no FSROOT / | sed 's|^/||')")
        out=("${extra[@]}" "${out[@]}")
    fi
    echo "${out[*]}"
}

# Print the ESP path that holds Windows Boot Manager (ours first, then any
# other ESP mounted read-only under /run/archsetup/esp-N). Non-zero if none.
find_windows_esp() {
    local esp i=0 dev mp
    esp=$(esp_path 2>/dev/null) && [[ -f $esp/EFI/Microsoft/Boot/bootmgfw.efi ]] && { echo "$esp"; return; }
    while read -r dev; do
        [[ $(findmnt -no TARGET "$dev" 2>/dev/null) == "$esp" ]] && continue
        mp=/run/archsetup/esp-$((i++)); mkdir -p "$mp"
        mountpoint -q "$mp" || mount -o ro "$dev" "$mp" 2>/dev/null || continue
        [[ -f $mp/EFI/Microsoft/Boot/bootmgfw.efi ]] && { echo "$mp"; return; }
        umount "$mp" 2>/dev/null
    done < <(lsblk -rnpo PATH,PARTTYPE | awk 'tolower($2)=="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"{print $1}')
    return 1
}
