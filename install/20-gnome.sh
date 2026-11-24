#!/usr/bin/env bash
# Module: gnome — extensions, dock, top bar, tiling, launcher and shortcuts.
# Sourced by install.sh (DUCAL_ROOT and lib/common.sh are already loaded).

# shellcheck source=../lib/groups.sh
source "$DUCAL_ROOT/lib/groups.sh"
if ! group_on gnome; then
  log_ok "GNOME desktop not chosen, skipping"
  return 0
fi

# shellcheck source=../lib/gnome.sh
source "$DUCAL_ROOT/lib/gnome.sh"

has_cmd gnome-shell || die "GNOME Shell not found: ducal needs a GNOME desktop"

# Only the extensions that installed get enabled
installed=()
for uuid in "${DUCAL_EXTENSIONS[@]}"; do
  if install_extension "$uuid"; then installed+=("$uuid"); fi
done
DUCAL_EXTENSIONS=("${installed[@]}")
# Without dash-to-dock, keep Ubuntu's dock: it reads the same dock settings
if [[ " ${DUCAL_EXTENSIONS[*]} " != *" dash-to-dock@micxgx.gmail.com "* ]]; then
  kept=()
  for uuid in "${DUCAL_CONFLICTING_EXTENSIONS[@]}"; do
    [[ $uuid == ubuntu-dock@ubuntu.com ]] || kept+=("$uuid")
  done
  DUCAL_CONFLICTING_EXTENSIONS=("${kept[@]}")
fi
log_ok "Extensions installed"

update_extension_lists
for uuid in "${DUCAL_CONFLICTING_EXTENSIONS[@]}"; do
  gnome-extensions disable "$uuid" 2>/dev/null || true
done
log_ok "Extensions enabled (new ones load at your next login)"

# Strip comments: dconf load does not accept them
grep -vE '^\s*#' "$DUCAL_ROOT/config/gnome/settings.ini" | dconf load /
log_ok "Desktop settings applied"

add_custom_keybinding ducal-search "Search the web" "$HOME/.local/bin/ducal search" "<Super>b"
log_ok "Super+B opens a web search box"

# Ctrl+Alt+T opens kitty instead of GNOME Terminal
gsettings set org.gnome.desktop.default-applications.terminal exec "$HOME/.local/bin/kitty"
# Ubuntu 25.04+ asks xdg-terminal-exec, which reads this list (first line wins)
terminals="$HOME/.config/ubuntu-xdg-terminals.list"
mkdir -p "$(dirname "$terminals")"
{
  echo kitty.desktop
  [[ -f $terminals ]] && grep -vx 'kitty.desktop' "$terminals"
} >"$terminals.new" || true
mv "$terminals.new" "$terminals"
log_ok "Ctrl+Alt+T opens kitty"
