#!/usr/bin/env bash
# end-4 illogical-impulse (upstream or tyLingyu's fork) on Hyprland.
# Its setup must run as a normal user and always uses yay, so give it yay
# from archlinuxcn instead of letting it build yay-bin.

case $DESKTOP in
    end4)    url=https://github.com/end-4/dots-hyprland ;;
    end4-ty) url=https://github.com/tyLingyu/end4-dots ;;
esac

pac yay git

# keep the clone: `./setup install` / `exp-update` are re-run from it later
dir=$(user_home)/.local/share/archsetup/${url##*/}
if [[ -d $dir/.git ]]; then
    run as_user git -C "$dir" pull --ff-only
else
    as_user mkdir -p "$(dirname "$dir")"
    run as_user git clone --depth 1 "$url" "$dir"
fi

# -f: no prompts, -s: we already did -Syu
run as_user_bus bash -c "cd '$dir' && ./setup install --force --skip-sysupdate"
