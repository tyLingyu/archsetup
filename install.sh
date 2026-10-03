#!/usr/bin/env bash
# ==============================================================================
# archsetup main installer (stage 2, dialog TUI)
#
# Phase 1 (wizard): every question is asked up front, answers are saved to
#                   /var/lib/archsetup/answers.conf (passwords only as hashes).
# Phase 2 (run):    modules/*.sh run unattended; finished modules are recorded
#                   in /var/lib/archsetup/progress so a re-run resumes.
# ==============================================================================
set -uo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# kmscon resets the environment
export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin HOME=${HOME:-/root}

source "$REPO_DIR/lib/common.sh"
source "$REPO_DIR/lib/i18n.sh"
source "$REPO_DIR/lib/apps.sh"

[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }
mkdir -p "$STATE_DIR"; touch "$LOG_FILE"

UI_LANG=en GH_PROXY=""
[[ -f $CONF_FILE ]] && source "$CONF_FILE"
if [[ $UI_LANG == zh ]]; then export LANG=zh_CN.UTF-8; else export LANG=C.UTF-8; fi
export UI_LANG GH_PROXY REPO_DIR

command -v dialog &>/dev/null || pacman -S --needed --noconfirm dialog

MODULES=(
    10-mirrors      # reflector
    11-repos        # multilib, archlinuxcn, chaotic-aur, paru, gh-proxy for makepkg
    20-base         # timezone, locale, hostname, root, user, sudo
    30-network
    40-bootloader
    50-gpu
    60-desktop
    70-apps
    99-finish
)

# ==============================================================================
# Wizard steps — each returns non-zero when the user pressed Back
# ==============================================================================

# ---- desktop: shell first, compositor is derived from it ---------------------
w_desktop() {
    local d
    d=$(d_menu "$(t desk_title)" "$(t desk_text)" "${DESKTOP:-kde}" \
        minimal   "$(t desk_minimal)" \
        gnome     "GNOME" \
        kde       "KDE Plasma" \
        dms       "DankMaterialShell        (niri / Hyprland)" \
        noctalia  "Noctalia                 (niri / Hyprland)" \
        caelestia "Caelestia                (Hyprland)" \
        end4      "end-4 illogical-impulse  (Hyprland)" \
        end4-ty   "tyLingyu/end4-dots       (Hyprland)") || return 1

    local c=""
    case $d in
        dms|noctalia)
            c=$(d_menu "$(t comp_title)" "$(t comp_text "$d")" "${COMPOSITOR:-niri}" \
                niri     "niri     — $(t comp_niri)" \
                hyprland "Hyprland — $(t comp_hypr)") || return 1 ;;
        caelestia|end4|end4-ty) c=hyprland ;;
    esac
    save_answer DESKTOP "$d"
    save_answer COMPOSITOR "$c"
}

# ---- repos -------------------------------------------------------------------
w_repos() {
    if grep -q '^\[chaotic-aur\]' /etc/pacman.conf; then
        save_answer USE_CHAOTIC present
    elif d_yesno "chaotic-aur" "$(t chaotic_text)"; then
        save_answer USE_CHAOTIC yes
    else
        [[ $? -eq 1 ]] && save_answer USE_CHAOTIC no || return 1
    fi
}

# ---- timezone ----------------------------------------------------------------
w_timezone() {
    local cur def tz
    cur=$(readlink -f /etc/localtime 2>/dev/null); cur=${cur#/usr/share/zoneinfo/}
    def=${TIMEZONE:-${cur:-$([[ $UI_LANG == zh ]] && echo Asia/Shanghai || echo UTC)}}
    while :; do
        tz=$(d_input "$(t tz_title)" "$(t tz_text "${cur:-$(t none)}")" "$def") || return 1
        [[ -f /usr/share/zoneinfo/$tz && -n $tz ]] && break
        d_msg "$(t tz_title)" "$(t tz_invalid "$tz")"
    done
    save_answer TIMEZONE "$tz"
}

# ---- locale ------------------------------------------------------------------
w_locale() {
    local cur l
    cur=$(sed -n 's/^LANG=//p' /etc/locale.conf 2>/dev/null)
    l=$(d_menu "$(t loc_title)" "$(t loc_text "${cur:-$(t none)}")" "${SYS_LANG:-${cur:-en_US.UTF-8}}" \
        en_US.UTF-8 "$(t loc_en)" \
        zh_CN.UTF-8 "$(t loc_zh)") || return 1
    save_answer SYS_LANG "$l"
}

# ---- hostname ----------------------------------------------------------------
w_hostname() {
    local cur h
    cur=$(cat /etc/hostname 2>/dev/null)
    while :; do
        h=$(d_input "$(t host_title)" "$(t host_text "${cur:-$(t none)}")" "${HOSTNAME_NEW:-${cur:-archlinux}}") || return 1
        [[ $h =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,62})$ ]] && break
        d_msg "$(t host_title)" "$(t host_invalid)"
    done
    save_answer HOSTNAME_NEW "$h"
}

# ---- root password -----------------------------------------------------------
w_root() {
    local hash
    if [[ $(passwd -S root 2>/dev/null | awk '{print $2}') == P ]]; then
        d_noyes "$(t root_title)" "$(t root_isset)"
        case $? in
            0) ;;                                        # yes, change it
            1) save_answer ROOT_HASH ""; return 0 ;;     # keep
            *) return 1 ;;
        esac
    fi
    hash=$(d_newpass "$(t root_title)") || return 1
    save_answer ROOT_HASH "$hash"
}

# ---- regular user ------------------------------------------------------------
w_user() {
    local users=() items=() u choice name hash=""
    mapfile -t users < <(awk -F: '$3>=1000 && $3<60000 {print $1}' /etc/passwd)
    if ((${#users[@]})); then
        for u in "${users[@]}"; do items+=("$u" "$(t user_existing)"); done
        items+=("+new" "$(t user_new)")
        choice=$(d_menu "$(t user_title)" "$(t user_pick)" "${USER_NAME:-${users[0]}}" "${items[@]}") || return 1
    else
        choice="+new"
    fi

    if [[ $choice == "+new" ]]; then
        while :; do
            name=$(d_input "$(t user_title)" "$(t user_name)" "${USER_NEW:+$USER_NAME}") || return 1
            if [[ ! $name =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then d_msg "$(t user_title)" "$(t user_invalid)"
            elif id "$name" &>/dev/null; then d_msg "$(t user_title)" "$(t user_exists "$name")"
            else break; fi
        done
        hash=$(d_newpass "$(t user_pass_title "$name")") || return 1
        save_answer USER_NEW 1
    else
        name=$choice
        if [[ $(passwd -S "$name" | awk '{print $2}') != P ]] \
           || d_noyes "$(t user_title)" "$(t user_chpass "$name")"; then
            hash=$(d_newpass "$(t user_pass_title "$name")") || return 1
        fi
        save_answer USER_NEW ""
    fi
    save_answer USER_NAME "$name"
    save_answer USER_HASH "$hash"
}

# ---- network -----------------------------------------------------------------
NET_SERVICES=(NetworkManager systemd-networkd iwd dhcpcd connman wpa_supplicant)

w_network() {
    local s found=() n
    for s in "${NET_SERVICES[@]}"; do
        systemctl is-enabled "$s" &>/dev/null && found+=("$s")
    done
    if ((${#found[@]})); then
        d_noyes "$(t net_title)" "$(t net_found "${found[*]}")"
        case $? in
            0) ;;
            1) save_answer NETWORK keep; return 0 ;;
            *) return 1 ;;
        esac
    fi
    n=$(d_menu "$(t net_title)" "$(t net_pick)" "${NETWORK:-nm}" \
        nm          "NetworkManager ($(t recommended))" \
        nm-iwd      "NetworkManager + iwd (WiFi backend)" \
        networkd    "systemd-networkd + systemd-resolved + iwd") || return 1
    save_answer NETWORK "$n"
}

# ---- bootloader --------------------------------------------------------------
detect_bootloaders() {
    local esp; esp=$(esp_path 2>/dev/null)
    bootctl is-installed &>/dev/null && echo systemd-boot
    { [[ -f /boot/grub/grub.cfg ]] || compgen -G "${esp:-/nonexistent}/EFI/*/grubx64.efi" >/dev/null; } && echo grub
    { pacman -Qq limine &>/dev/null || compgen -G "${esp:-/nonexistent}/EFI/limine/*" >/dev/null; } && echo limine
    [[ -n $esp && -d $esp/EFI/refind ]] && echo refind
    return 0
}

w_bootloader() {
    local found=() items=() b text def
    mapfile -t found < <(detect_bootloaders)

    if ((${#found[@]})); then
        text=$(t boot_found "${found[*]}")
        items+=(keep "$(t boot_keep "${found[*]}")")
        def=keep
    else
        text=$(t boot_none)
        def=$(is_uefi && echo systemd-boot || echo grub)
    fi
    if is_uefi; then
        items+=(systemd-boot "systemd-boot" grub "GRUB" limine "Limine" refind "rEFInd")
    else
        text+="\n\n$(t boot_bios)"
        items+=(grub "GRUB" limine "Limine")
    fi

    b=$(d_menu "$(t boot_title)" "$text" "${BOOTLOADER:-$def}" "${items[@]}") || return 1
    save_answer BOOTLOADER "$b"
    save_answer BOOT_OLD "${found[*]}"
}

# ---- apps (one checklist per category; Back walks to the previous category) ---
w_apps() {
    local i=0 n=${#APP_CATEGORIES[@]} cat sel
    declare -A picked=()
    local -a prev=()
    read -ra prev <<<"${APPS:-}"
    while ((i < n)); do
        cat=${APP_CATEGORIES[$i]}
        local items=() line pkgs desc def state
        while IFS='|' read -r pkgs desc def; do
            if [[ -n ${APPS+x} ]]; then
                [[ " ${prev[*]} " == *" ${pkgs%% *} "* ]] && state=on || state=off
            else
                state=$def
            fi
            items+=("${pkgs%% *}" "$desc" "$state")
        done < <(apps_in "$cat")
        if sel=$(d_check "$(t apps_title) ($((i+1))/$n)" "$(t "cat_$cat")" "${items[@]}"); then
            picked[$cat]=$sel
            ((i++))
        else
            ((i == 0)) && return 1
            ((i--))
        fi
    done
    save_answer APPS "$(printf '%s\n' "${picked[@]}" | xargs)"
}

# ---- summary -----------------------------------------------------------------
w_summary() {
    local s
    s+="$(t sum_desktop): \Zb${DESKTOP}${COMPOSITOR:+ + $COMPOSITOR}\Zn\n"
    s+="chaotic-aur: ${USE_CHAOTIC}    GitHub proxy: ${GH_PROXY:-$(t none)}\n"
    s+="$(t sum_tz): ${TIMEZONE}    LANG: ${SYS_LANG}\n"
    s+="$(t sum_host): ${HOSTNAME_NEW}\n"
    s+="$(t sum_user): ${USER_NAME}$([[ -n $USER_NEW ]] && echo " ($(t new))")\n"
    s+="$(t sum_net): ${NETWORK}\n"
    s+="$(t sum_boot): ${BOOTLOADER}${BOOT_OLD:+ ($(t detected): $BOOT_OLD)}\n"
    s+="GPU: $(lspci | grep -E 'VGA|3D|Display' | sed 's/^[^:]*: //' | paste -sd ';' | cut -c1-120)\n"
    s+="$(t sum_apps): ${APPS:-$(t none)}\n\n"
    s+="$(t sum_confirm)"
    _dlg --title "$(t sum_title)" --yes-label "$(t start)" --no-label "$(t back)" --yesno "$s" 0 0
}

WIZARD=(w_desktop w_repos w_timezone w_locale w_hostname w_root w_user w_network w_bootloader w_apps w_summary)

wizard() {
    local i=0
    while ((i < ${#WIZARD[@]})); do
        if "${WIZARD[$i]}"; then
            ((i++))
        elif ((i == 0)); then
            d_noyes "$(t quit_title)" "$(t quit_text)" && { clear; exit 0; }
        else
            ((i--))
        fi
    done
    save_answer WIZARD_DONE 1
}

# ==============================================================================
# Run phase
# ==============================================================================
run_modules() {
    local m rc
    # as_user() adds a temporary NOPASSWD rule for paru; always drop it
    trap 'rm -f "$TMP_SUDOERS"' EXIT

    for m in "${MODULES[@]}"; do
        if is_done "$m"; then
            printf '%s  ↷ %s (done)%s\n' "$D" "$m" "$N"; continue
        fi
        while :; do
            section "$m"
            ( set -Eeo pipefail; source "$REPO_DIR/modules/$m.sh" )
            rc=$?
            ((rc == 0)) && { mark_done "$m"; break; }
            err "$(t mod_failed "$m" "$rc")"
            case $(d_menu "$(t mod_failed_title)" "$(t mod_failed_text "$m" "$LOG_FILE")" retry \
                     retry "$(t retry)" skip "$(t skip)" abort "$(t abort)") in
                retry) clear ;;
                skip)  clear; warn "Skipped $m"; break ;;
                *)     clear; exit "$rc" ;;
            esac
        done
    done
}

main() {
    load_answers
    if [[ ${WIZARD_DONE:-} == 1 ]]; then
        case $(d_menu "$(t resume_title)" "$(t resume_text)" resume \
                 resume "$(t resume)" restart "$(t restart)") in
            resume)  ;;
            restart) rm -f "$ANSWERS_FILE" "$PROGRESS_FILE"; unset WIZARD_DONE; load_answers; wizard ;;
            *)       clear; exit 0 ;;
        esac
    else
        wizard
    fi
    clear
    run_modules
}

main "$@"
