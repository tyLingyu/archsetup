#!/usr/bin/env bash
# Noctalia (v5, native) on niri or Hyprland: the compositor's stock config plus
# the integration snippets from docs.noctalia.dev.

wm_base
pac noctalia

home=$(user_home)

noctalia_niri() {
    local cfg=$home/.config/niri/config.kdl
    if [[ ! -f $cfg ]]; then
        as_user mkdir -p "$(dirname "$cfg")"
        as_user cp /usr/share/doc/niri/default-config.kdl "$cfg"
    fi
    grep -q 'spawn-at-startup "noctalia"' "$cfg" && return 0

    # niri rejects duplicate binds: drop stock binds that Noctalia takes over
    sed -i -E '/^\s*(Mod\+Space|Mod\+S|Mod\+Comma|Alt\+Tab|XF86AudioRaiseVolume|XF86AudioLowerVolume|XF86AudioMute|XF86MonBrightnessUp|XF86MonBrightnessDown)\s[^{]*\{.*\}\s*$/d' "$cfg"

    # add the Noctalia binds inside the existing binds block
    sed -i '/^binds {/r /dev/stdin' "$cfg" <<'EOF'
    // ---- Noctalia (added by archsetup) ----
    Mod+Space { spawn-sh "noctalia msg panel-toggle launcher"; }
    Mod+S { spawn-sh "noctalia msg panel-toggle control-center"; }
    Mod+Comma { spawn-sh "noctalia msg settings-toggle"; }
    Alt+Tab { spawn-sh "noctalia msg window-switcher hold"; }
    XF86AudioRaiseVolume allow-when-locked=true { spawn-sh "noctalia msg volume-up"; }
    XF86AudioLowerVolume allow-when-locked=true { spawn-sh "noctalia msg volume-down"; }
    XF86AudioMute allow-when-locked=true { spawn-sh "noctalia msg volume-mute"; }
    XF86MonBrightnessUp allow-when-locked=true { spawn-sh "noctalia msg brightness-up"; }
    XF86MonBrightnessDown allow-when-locked=true { spawn-sh "noctalia msg brightness-down"; }
EOF

    cat >> "$cfg" <<'EOF'

// ---- Noctalia (added by archsetup, see docs.noctalia.dev) ----
spawn-at-startup "noctalia"

window-rule {
    geometry-corner-radius 20
    clip-to-geometry true
}

window-rule {
    match app-id="dev.noctalia.Noctalia"
    open-floating true
    default-column-width { fixed 1080; }
    default-window-height { fixed 920; }
}

layer-rule {
    match namespace="^noctalia-backdrop"
    place-within-backdrop true
}

debug {
    honor-xdg-activation-with-invalid-serial
}
EOF
    chown "$USER_NAME:" "$cfg"
    as_user niri validate -c "$cfg" || warn "niri validate reported problems in $cfg"
}

noctalia_hyprland() {
    local cfg=$home/.config/hypr/hyprland.lua
    if [[ ! -f $cfg ]]; then
        as_user mkdir -p "$(dirname "$cfg")"
        as_user cp /usr/share/hypr/hyprland.lua "$cfg"
    fi
    grep -q 'exec_cmd("noctalia")' "$cfg" && return 0
    cat >> "$cfg" <<'EOF'

-- ---- Noctalia (added by archsetup, see docs.noctalia.dev) ----
hl.on("hyprland.start", function()
  hl.exec_cmd("noctalia")
end)

local noctalia = "noctalia msg "
hl.bind("SUPER + Space", hl.dsp.exec_cmd(noctalia .. "panel-toggle launcher"))
hl.bind("SUPER + S", hl.dsp.exec_cmd(noctalia .. "panel-toggle control-center"))
hl.bind("SUPER + comma", hl.dsp.exec_cmd(noctalia .. "settings-toggle"))
hl.bind("ALT + Tab", hl.dsp.exec_cmd(noctalia .. "window-switcher hold"))
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(noctalia .. "volume-up"))
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(noctalia .. "volume-down"))
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(noctalia .. "volume-mute"))
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(noctalia .. "brightness-up"))
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(noctalia .. "brightness-down"))

hl.window_rule({
    match = { class = "dev.noctalia.Noctalia" },
    float = true,
    size = { 1080, 920 },
})

hl.layer_rule({
  name = "noctalia",
  match = {
    namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd|window-switcher)$",
  },
  no_anim = true,
  ignore_alpha = 0.5,
  blur = true,
  blur_popups = true,
})
EOF
    chown "$USER_NAME:" "$cfg"
}

"noctalia_$COMPOSITOR"
