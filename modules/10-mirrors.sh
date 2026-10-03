#!/usr/bin/env bash
# Refresh the official mirrorlist with reflector.

pac reflector

ml=/etc/pacman.d/mirrorlist
cp -f "$ml" "$ml.archsetup.bak"

args=(--protocol https --age 12 --fastest 10 --sort rate --save "$ml")
if is_cn; then
    country=China
else
    country=$(curl -fsS --max-time 3 https://ipinfo.io/country 2>/dev/null | tr -d '\r\n' || true)
fi
info "reflector country: ${country:-any}"

if run reflector "${args[@]}" ${country:+--country "$country"}; then
    ok "Mirrorlist updated."
elif run reflector "${args[@]}" --latest 30; then
    ok "Mirrorlist updated (global latest 30)."
else
    warn "reflector failed, keeping the previous mirrorlist."
    cp -f "$ml.archsetup.bak" "$ml"
fi

run pacman -Syy
