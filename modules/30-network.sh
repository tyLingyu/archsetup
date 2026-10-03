#!/usr/bin/env bash
# Network stack. Services are only *enabled* here (not restarted) so the
# running connection keeps working for the rest of the install; the new
# stack takes over after reboot.

disable_except() {
    local keep=" $* " s
    for s in NetworkManager systemd-networkd iwd dhcpcd connman wpa_supplicant; do
        [[ $keep == *" $s "* ]] && continue
        systemctl is-enabled "$s" &>/dev/null && run systemctl disable "$s"
    done
    return 0
}

case $NETWORK in
    keep)
        ok "Keeping the current network setup."
        ;;
    nm)
        pac networkmanager
        disable_except NetworkManager
        svc_enable NetworkManager
        ;;
    nm-iwd)
        pac networkmanager iwd
        mkdir -p /etc/NetworkManager/conf.d
        printf '[device]\nwifi.backend=iwd\n' > /etc/NetworkManager/conf.d/wifi_backend.conf
        # NetworkManager starts iwd itself
        disable_except NetworkManager
        svc_enable NetworkManager
        ;;
    networkd)
        pac iwd
        mkdir -p /etc/systemd/network
        cat > /etc/systemd/network/20-wired.network <<'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes

[DHCPv4]
RouteMetric=100
EOF
        cat > /etc/systemd/network/25-wireless.network <<'EOF'
[Match]
Name=wl*

[Link]
RequiredForOnline=routable

[Network]
DHCP=yes
IgnoreCarrierLoss=3s

[DHCPv4]
RouteMetric=600
EOF
        disable_except systemd-networkd iwd
        svc_enable systemd-networkd iwd
        run systemctl enable --now systemd-resolved
        ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
        ;;
esac
