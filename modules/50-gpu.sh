#!/usr/bin/env bash
# Graphics drivers, detected from lspci. NVIDIA always gets nvidia-open-dkms.

gpus=$(lspci | grep -E 'VGA|3D|Display' || true)
info "GPUs:"; sed 's/^/      /' <<<"$gpus"

svcs=()
pkgs=(mesa lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader vulkan-tools)
has_nvidia=0 has_other=0

if grep -qi 'intel' <<<"$gpus"; then
    pkgs+=(vulkan-intel lib32-vulkan-intel intel-media-driver)
    has_other=1
fi
if grep -Eqi 'AMD|ATI|Radeon' <<<"$gpus"; then
    pkgs+=(vulkan-radeon lib32-vulkan-radeon)
    has_other=1
fi
if grep -qi 'nvidia' <<<"$gpus"; then
    has_nvidia=1
    # nvidia-open only supports Turing (GTX 16xx / RTX 20xx) and newer
    if grep -Eqi 'GTX (9[0-9]{2}|10[0-9]{2})|GT 10[0-9]{2}|Quadro [MKP][0-9]|TITAN (X|Xp|V)\b' <<<"$gpus"; then
        warn "This NVIDIA card looks older than Turing; nvidia-open-dkms will NOT drive it."
        warn "Consider nvidia-580xx-dkms (AUR) after the install."
    fi
    for k in $(cat /usr/lib/modules/*/pkgbase 2>/dev/null | sort -u); do pkgs+=("$k-headers"); done
    pkgs+=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings libva-nvidia-driver egl-wayland)
    ((has_other)) && pkgs+=(nvidia-prime)       # hybrid laptop: prime-run
fi

# virtual machines
case $(systemd-detect-virt 2>/dev/null || true) in
    kvm|qemu) pkgs+=(qemu-guest-agent spice-vdagent); svcs=(qemu-guest-agent) ;;
    vmware)   pkgs+=(open-vm-tools); svcs=(vmtoolsd vmware-vmblock-fuse) ;;
    oracle)   pkgs+=(virtualbox-guest-utils); svcs=(vboxservice) ;;
esac

pac "${pkgs[@]}"
((${#svcs[@]})) && svc_enable "${svcs[@]}"

if ((has_nvidia)); then
    # the kms hook would pull nouveau into the initramfs (Arch wiki: NVIDIA)
    if grep -Eq '^HOOKS=.*\bkms\b' /etc/mkinitcpio.conf; then
        sed -i -E '/^HOOKS=/ s/ kms\b//' /etc/mkinitcpio.conf
        ok "Removed kms hook from mkinitcpio."
    fi
    svc_enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service
    run mkinitcpio -P
fi
ok "Graphics drivers installed."
