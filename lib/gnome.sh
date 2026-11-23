#!/usr/bin/env bash
# GNOME Shell helpers for ducal. Source after lib/common.sh.

DUCAL_EXTENSIONS=(
  user-theme@gnome-shell-extensions.gcampax.github.com # custom shell theme (ducal theme)
  blur-my-shell@aunetx                                 # blur behind the dock
  dash-to-dock@micxgx.gmail.com                        # auto-hiding dock
  just-perfection-desktop@just-perfection              # slim top bar
  search-light@icedman.github.com                      # launcher on Super+Space
  forge@jmmaranan.com                                  # tiling windows
  space-bar@luchrioh                                   # numbered workspaces in the top bar
)

# Ubuntu defaults that clash with the ducal setup
DUCAL_CONFLICTING_EXTENSIONS=(
  ubuntu-dock@ubuntu.com      # replaced by dash-to-dock
  tiling-assistant@ubuntu.com # clashes with Forge
  ding@rastersoft.com         # desktop icons
)

shell_major_version() { gnome-shell --version | awk '{print $3}' | cut -d. -f1; }

is_extension_installed() { gnome-extensions list 2>/dev/null | grep -qx "$1"; }

# install_extension UUID — downloads the build for this GNOME Shell version
# from extensions.gnome.org. New extensions load at the next login.
# Fails with a warning when there is no build: a new GNOME often comes out
# before every extension supports it, and the rest of the desktop still installs.
install_extension() {
  local uuid=$1 version info path tmp
  is_extension_installed "$uuid" && return 0
  version=$(shell_major_version)
  if ! info=$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=$uuid&shell_version=$version"); then
    log_warn "$uuid is not available for GNOME Shell $version, skipping it"
    return 1
  fi
  if ! path=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["download_url"])' <<<"$info"); then
    log_warn "Unexpected answer from extensions.gnome.org for $uuid, skipping it"
    return 1
  fi
  tmp=$(mktemp -d)
  log_step "Installing extension $uuid"
  curl -fsSL --retry 3 -o "$tmp/ext.zip" "https://extensions.gnome.org$path" || die "Download failed: $uuid"
  gnome-extensions install --force "$tmp/ext.zip"
  rm -rf "$tmp"
}

# add_custom_keybinding ID NAME COMMAND BINDING — a GNOME custom shortcut,
# added once and kept next to the user's own custom shortcuts.
add_custom_keybinding() {
  local id=$1 name=$2 command=$3 binding=$4 list path
  path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/$id/"
  list=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
  list=$(python3 - "$list" "$path" <<'EOF'
import ast, sys
value, path = sys.argv[1].strip(), sys.argv[2]
if value.startswith("@as "):
    value = value[4:]
paths = ast.literal_eval(value) if value else []
if path not in paths:
    paths.append(path)
print(str(paths))
EOF
  )
  gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$list"
  dconf write "${path}name" "'$name'"
  dconf write "${path}command" "'$command'"
  dconf write "${path}binding" "'$binding'"
}

# update_extension_lists — enables ducal extensions and disables the conflicting
# ones, keeping every other extension the user has.
update_extension_lists() {
  local enabled disabled result
  enabled=$(gsettings get org.gnome.shell enabled-extensions)
  disabled=$(gsettings get org.gnome.shell disabled-extensions)
  result=$(python3 - "$enabled" "$disabled" "${DUCAL_EXTENSIONS[*]}" "${DUCAL_CONFLICTING_EXTENSIONS[*]}" <<'EOF'
import ast, sys

def parse(value):
    value = value.strip()
    if value.startswith("@as "):
        value = value[4:]
    return ast.literal_eval(value) if value else []

enabled, disabled = parse(sys.argv[1]), parse(sys.argv[2])
ours, conflicting = sys.argv[3].split(), sys.argv[4].split()
enabled = [e for e in enabled if e not in conflicting] + [e for e in ours if e not in enabled]
disabled = [d for d in disabled if d not in ours] + [c for c in conflicting if c not in disabled]
print(str(enabled))
print(str(disabled))
EOF
  )
  gsettings set org.gnome.shell enabled-extensions "$(sed -n 1p <<<"$result")"
  gsettings set org.gnome.shell disabled-extensions "$(sed -n 2p <<<"$result")"
}
