#!/usr/bin/env bash
# Shared pieces for every desktop.

# audio, bluetooth, portals, user dirs — every desktop needs these
desktop_base() {
    pac pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber \
        bluez bluez-utils xdg-user-dirs xdg-utils polkit
    svc_enable bluetooth.service
    as_user xdg-user-dirs-update || true
}

# niri / Hyprland family: compositor + the usual Wayland toolbox
wm_base() {
    pac kitty nautilus xdg-desktop-portal-gtk qt5-wayland qt6-wayland \
        brightnessctl playerctl wl-clipboard cliphist grim slurp
    case $COMPOSITOR in
        niri)     pac niri xwayland-satellite xdg-desktop-portal-gnome ;;
        hyprland) pac hyprland xdg-desktop-portal-hyprland ;;
    esac
}

# command a greeter should start for the chosen compositor
session_cmd() {
    case $COMPOSITOR in
        niri)     echo niri-session ;;
        hyprland) echo start-hyprland ;;
    esac
}

write_greetd() {   # write_greetd "<greeter command>"
    mkdir -p /etc/greetd
    cat > /etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[default_session]
command = "$1"
user = "greeter"
EOF
}

setup_dm() {
    # only one display-manager.service alias may exist
    systemctl disable display-manager.service &>/dev/null || true

    case $DM in
        gdm)
            pac gdm
            svc_enable gdm.service
            ;;
        plasmalogin)
            pac plasma-login-manager
            svc_enable plasmalogin.service
            ;;
        sddm-silent)
            pac sddm
            pkg sddm-silent-theme
            mkdir -p /etc/sddm.conf.d
            cat > /etc/sddm.conf.d/10-silent.conf <<'EOF'
# installed by archsetup (SilentSDDM)
[General]
InputMethod=qtvirtualkeyboard
GreeterEnvironment=QML2_IMPORT_PATH=/usr/share/sddm/themes/silent/components/,QT_IM_MODULE=qtvirtualkeyboard

[Theme]
Current=silent
EOF
            svc_enable sddm.service
            ;;
        tuigreet)
            pac greetd greetd-tuigreet
            write_greetd "tuigreet --time --remember --remember-session --asterisks --cmd $(session_cmd)"
            svc_enable greetd.service
            ;;
        shell-greeter)
            pac greetd
            case $DESKTOP in
                dms)
                    pkg greetd-dms-greeter-git
                    write_greetd "/usr/bin/dms-greeter --command $COMPOSITOR"
                    # copy the user's DMS theme to the greeter (defaults on first run)
                    as_user sudo dms-greeter sync || warn "dms-greeter sync failed; run it after first login."
                    ;;
                noctalia)
                    pkg noctalia-greeter
                    noctalia-greeter-print-greetd-config > /etc/greetd/config.toml
                    ;;
            esac
            svc_enable greetd.service
            ;;
        ly)
            pac ly
            run systemctl disable getty@tty2.service || true
            svc_enable ly@tty2.service
            ;;
        none)
            ok "No login manager: log in on a tty and run $(session_cmd)"
            ;;
    esac
}
