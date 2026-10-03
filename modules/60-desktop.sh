#!/usr/bin/env bash
# Desktop environment / compositor + shell + login manager.

[[ $DESKTOP == minimal ]] && { ok "Minimal install: no desktop."; return 0; }

D=$REPO_DIR/modules/desktop
source "$D/common.sh"

desktop_base
case $DESKTOP in
    gnome)        source "$D/gnome.sh" ;;
    kde)          source "$D/kde.sh" ;;
    dms)          source "$D/dms.sh" ;;
    noctalia)     source "$D/noctalia.sh" ;;
    caelestia)    source "$D/caelestia.sh" ;;
    end4|end4-ty) source "$D/end4.sh" ;;
    *)            die "Unknown desktop: $DESKTOP" ;;
esac
setup_dm
ok "Desktop ready: $DESKTOP${COMPOSITOR:+ + $COMPOSITOR}, login: $DM"
