#!/usr/bin/env bash
# ==============================================================================
# archsetup bootstrap (stage 1, pure bash)
#
#   curl -fsSL https://raw.githubusercontent.com/tyLingyu/archsetup/main/bootstrap.sh | bash
#   # behind the GFW:
#   curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/tyLingyu/archsetup/main/bootstrap.sh | bash
#
# Assumes a freshly pacstrapped Arch Linux, booted, logged in as root on a tty.
#   1. sanity checks (root / not live ISO / network)
#   2. language selection (zh -> noto-fonts-cjk + kmscon)
#   3. install git + dialog
#   4. pick GitHub or a gh-proxy mirror (ping, optional real clone speed test)
#   5. clone the repo and launch install.sh (inside kmscon for zh)
# ==============================================================================
set -euo pipefail

REPO="tyLingyu/archsetup"
BRANCH="${BRANCH:-main}"
TARGET_DIR="${TARGET_DIR:-/opt/archsetup}"
STATE_DIR="/var/lib/archsetup"
CONF_FILE="$STATE_DIR/bootstrap.conf"
GH_PROXIES=(v6.gh-proxy.org v4.gh-proxy.org hk.gh-proxy.org gh-proxy.org)
CJK_FONT="Noto Sans Mono CJK SC"

R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' B=$'\e[34m' C=$'\e[36m' D=$'\e[2m' N=$'\e[0m'

info() { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s  !%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '%sERROR:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

# stdin is the pipe when run via `curl | bash`, so always read from the tty
ask() {
    local prompt="$1" default="${2:-}" reply
    read -r -p "$prompt" reply < /dev/tty || true
    printf '%s' "${reply:-$default}"
}

# ------------------------------------------------------------------------------
# 1. sanity checks
# ------------------------------------------------------------------------------
check_env() {
    [[ $(uname -m) == x86_64 ]] || die "Only x86_64 is supported."
    [[ $EUID -eq 0 ]] || die "Please run as root (no regular user exists yet on a fresh install)."
    [[ -f /etc/arch-release ]] || die "This is not Arch Linux."

    if [[ -d /run/archiso ]] || [[ $(awk '$2=="/"{print $3}' /proc/mounts) == overlay ]]; then
        die "Running from the live ISO. Reboot into the installed system first."
    fi
    if systemd-detect-virt --chroot &>/dev/null; then
        die "Running inside a chroot. Reboot into the installed system first."
    fi

    info "Checking network..."
    if ! curl -fsS --max-time 8 -o /dev/null https://archlinux.org; then
        warn "No network connection."
        echo "    Wired : systemctl enable --now systemd-networkd systemd-resolved (needs a .network file)"
        echo "    WiFi  : iwctl / nmtui, if iwd or networkmanager was pacstrapped"
        die "Connect to the internet and run this script again."
    fi
    ok "Network is up."

    while [[ -e /var/lib/pacman/db.lck ]] && pgrep -x pacman &>/dev/null; do
        warn "pacman is running, waiting..."; sleep 3
    done
}

# ------------------------------------------------------------------------------
# 2. language
# ------------------------------------------------------------------------------
select_language() {
    echo
    echo "Select installer language:"
    echo "  [1] English"
    echo "  [2] Chinese / Zhongwen  (installs noto-fonts-cjk ~190MB + kmscon for CJK on tty)"
    case "$(ask 'Choice [1]: ' 1)" in
        2) UI_LANG=zh ;;
        *) UI_LANG=en ;;
    esac
    ok "Language: $UI_LANG"
}

# ------------------------------------------------------------------------------
# 3. dependencies
# ------------------------------------------------------------------------------
install_deps() {
    local pkgs=(git dialog)
    [[ $UI_LANG == zh ]] && pkgs+=(noto-fonts-cjk kmscon)

    info "Installing: ${pkgs[*]}"
    # full -Syu: never do partial upgrades
    pacman -Syu --needed --noconfirm "${pkgs[@]}" || die "pacman failed."

    if [[ $UI_LANG == zh ]]; then
        # dialog needs a UTF-8 locale to draw CJK; generate it but do NOT set it
        # system-wide (the raw linux console can't render CJK)
        local l
        for l in en_US.UTF-8 zh_CN.UTF-8; do
            sed -i "s/^#\s*\(${l} UTF-8\)/\1/" /etc/locale.gen
        done
        locale-gen >/dev/null
        ok "Generated locales: en_US.UTF-8 zh_CN.UTF-8"
    fi
}

# ------------------------------------------------------------------------------
# 4. source selection
# ------------------------------------------------------------------------------
# SOURCES[i] = host, PREFIXES[i] = URL prefix to put in front of https://github.com/...
SOURCES=() PREFIXES=() LATENCY=() CLONE_TIME=()

repo_url() { printf '%shttps://github.com/%s.git' "${PREFIXES[$1]}" "$REPO"; }

ping_ms() {
    local out
    out=$(ping -c 3 -W 2 -q "$1" 2>/dev/null) || return 1
    # rtt min/avg/max/mdev = 1.1/2.2/3.3/0.4 ms
    awk -F'/' '/^rtt|^round-trip/{printf "%.1f", $5}' <<<"$out"
}

probe_sources() {
    SOURCES=(github.com "${GH_PROXIES[@]}")
    PREFIXES=("")
    local h
    for h in "${GH_PROXIES[@]}"; do PREFIXES+=("https://$h/"); done

    info "Pinging sources..."
    local i ms
    for i in "${!SOURCES[@]}"; do
        if ms=$(ping_ms "${SOURCES[$i]}") && [[ -n $ms ]]; then
            LATENCY[i]=$ms
        else
            LATENCY[i]=""
        fi
    done
}

# prints the index of the best source (lowest clone time if tested, else lowest ping)
best_source() {
    local i best="" best_v=""
    for i in "${!SOURCES[@]}"; do
        local v="${CLONE_TIME[$i]:-}"
        [[ ${#CLONE_TIME[@]} -eq 0 ]] && v="${LATENCY[$i]:-}"
        [[ -z $v || $v == fail ]] && continue
        if [[ -z $best_v ]] || awk "BEGIN{exit !($v < $best_v)}"; then
            best=$i best_v=$v
        fi
    done
    printf '%s' "${best:-0}"
}

print_sources() {
    local i lat ct
    echo
    printf "  %-4s %-20s %-12s %s\n" "" "SOURCE" "PING" "CLONE"
    for i in "${!SOURCES[@]}"; do
        lat="${LATENCY[$i]:+${LATENCY[$i]} ms}"; lat="${lat:-${R}timeout${N}}"
        ct="${CLONE_TIME[$i]:-}"
        [[ $ct == fail ]] && ct="${R}failed${N}" || ct="${ct:+${ct} s}"
        printf "  [%d]  %-20s %-12b %b\n" "$i" "${SOURCES[$i]}" "$lat" "${ct:-${D}-${N}}"
    done
    echo
}

# real `git clone --depth 1` into $WORK/<i>; keeps the clones so we can reuse one
speed_test() {
    local i start
    info "Running real clone speed test (timeout 90s each)..."
    for i in "${!SOURCES[@]}"; do
        printf '    %-20s ' "${SOURCES[$i]}"
        start=$(date +%s.%N)
        if timeout 90 git clone -q --depth 1 -b "$BRANCH" "$(repo_url "$i")" "$WORK/$i" &>/dev/null; then
            CLONE_TIME[i]=$(awk "BEGIN{printf \"%.1f\", $(date +%s.%N) - $start}")
            printf '%s%ss%s\n' "$G" "${CLONE_TIME[$i]}" "$N"
        else
            CLONE_TIME[i]=fail
            rm -rf "${WORK:?}/$i"
            printf '%sfailed%s\n' "$R" "$N"
        fi
    done
}

select_source() {
    probe_sources
    print_sources

    # Clash/sing-box TUN fake-ip (198.18.0.0/15) makes ping meaningless
    if getent ahostsv4 github.com 2>/dev/null | awk 'NR==1{exit !($1 ~ /^198\.1[89]\./)}'; then
        warn "Fake-IP proxy detected (198.18.0.0/15): ping results are not reliable, use the clone test."
    fi

    if [[ $(ask "Run a real git clone speed test on every source? [y/N]: " n) =~ ^[Yy] ]]; then
        speed_test
        print_sources
    fi

    local def choice
    def=$(best_source)
    while :; do
        choice=$(ask "Use which source? [${def}]: " "$def")
        [[ $choice =~ ^[0-9]+$ && -n ${SOURCES[$choice]:-} ]] && break
        warn "Invalid choice."
    done
    SRC_IDX=$choice
    GH_PROXY="${PREFIXES[$choice]}"
    ok "Source: ${SOURCES[$choice]}"
}

# ------------------------------------------------------------------------------
# 5. fetch + launch
# ------------------------------------------------------------------------------
fetch_repo() {
    rm -rf "$TARGET_DIR"
    mkdir -p "$(dirname "$TARGET_DIR")"
    if [[ -d $WORK/$SRC_IDX/.git ]]; then
        mv "$WORK/$SRC_IDX" "$TARGET_DIR"
    else
        info "Cloning $(repo_url "$SRC_IDX")"
        local n
        for n in 1 2 3; do
            git clone -q --depth 1 -b "$BRANCH" "$(repo_url "$SRC_IDX")" "$TARGET_DIR" && break
            [[ $n -eq 3 ]] && die "Clone failed 3 times. Try another source."
            warn "Clone failed ($n/3), retrying..."; rm -rf "$TARGET_DIR"; sleep 2
        done
    fi
    ok "Repository ready at $TARGET_DIR"
}

write_conf() {
    mkdir -p "$STATE_DIR"
    cat > "$CONF_FILE" <<EOF
# written by bootstrap.sh — read by install.sh
UI_LANG=$UI_LANG
GH_PROXY=$GH_PROXY
REPO_DIR=$TARGET_DIR
EOF
}

launch() {
    local cmd=(/usr/bin/bash "$TARGET_DIR/install.sh")
    if [[ $UI_LANG == zh ]]; then
        info "Starting installer inside kmscon (Chinese UI)..."
        sleep 1
        # --reset-env is on by default: install.sh reads $CONF_FILE instead of env
        kmscon --vt=8 --switchvt --oneshot \
               --font-name "$CJK_FONT" --font-size 18 \
               -l -- "${cmd[@]}" \
            || warn "kmscon exited with an error."
    else
        rm -rf "$WORK"
        exec "${cmd[@]}" < /dev/tty
    fi
}

main() {
    clear || true
    printf '%s archsetup bootstrap %s\n\n' "$C" "$N"
    check_env
    select_language
    install_deps

    WORK=$(mktemp -d)
    trap 'rm -rf "$WORK"' EXIT

    select_source
    fetch_repo
    write_conf
    launch
}

main "$@"
