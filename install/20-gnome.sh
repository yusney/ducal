#!/usr/bin/env bash
# Module: gnome — extensions, dock, top bar, tiling, launcher and shortcuts.
# Sourced by install.sh (DUCAL_ROOT and lib/common.sh are already loaded).

# shellcheck source=../lib/gnome.sh
source "$DUCAL_ROOT/lib/gnome.sh"

has_cmd gnome-shell || die "GNOME Shell not found: ducal needs a GNOME desktop"

for uuid in "${DUCAL_EXTENSIONS[@]}"; do install_extension "$uuid"; done
log_ok "Extensions installed"

update_extension_lists
for uuid in "${DUCAL_CONFLICTING_EXTENSIONS[@]}"; do
  gnome-extensions disable "$uuid" 2>/dev/null || true
done
log_ok "Extensions enabled (new ones load at your next login)"

# Strip comments: dconf load does not accept them
grep -vE '^\s*#' "$DUCAL_ROOT/config/gnome/settings.ini" | dconf load /
log_ok "Desktop settings applied"
