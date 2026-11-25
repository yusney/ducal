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
  clipboard-indicator@tudmotu.com                      # clipboard history (Super+Shift+V)
)

# Ubuntu defaults that clash with the ducal setup
DUCAL_CONFLICTING_EXTENSIONS=(
  ubuntu-dock@ubuntu.com      # replaced by dash-to-dock
  tiling-assistant@ubuntu.com # clashes with Forge
  ding@rastersoft.com         # desktop icons
)

shell_major_version() { gnome-shell --version | awk '{print $3}' | cut -d. -f1; }

is_extension_installed() { gnome-extensions list 2>/dev/null | grep -qx "$1"; }

# installed_extension_supports UUID VERSION — false when the installed copy lists
# its GNOME Shell versions and VERSION is not one of them (GNOME will not load it)
installed_extension_supports() {
  local uuid=$1 version=$2 dir metadata=""
  for dir in "$HOME/.local/share/gnome-shell/extensions" /usr/share/gnome-shell/extensions; do
    [[ -f $dir/$uuid/metadata.json ]] && metadata=$dir/$uuid/metadata.json && break
  done
  [[ -n $metadata ]] || return 0
  python3 -c '
import json, sys
shells = json.load(open(sys.argv[1])).get("shell-version") or []
sys.exit(0 if not shells or any(str(v).split(".")[0] == sys.argv[2] for v in shells) else 1)
' "$metadata" "$version" 2>/dev/null || [[ $? -ne 1 ]]
}

# install_extension UUID — downloads the build for this GNOME Shell version
# from extensions.gnome.org. New extensions load at the next login.
# Fails with a warning when there is no build: a new GNOME often comes out
# before every extension supports it, and the rest of the desktop still installs.
# The site answers with its newest build even when that build does not list this
# GNOME Shell (GNOME would never load it), so the version list is checked too.
# An installed copy that does not support this GNOME Shell is replaced when a
# newer build does.
install_extension() {
  local uuid=$1 version info path rc=0 tmp
  version=$(shell_major_version)
  if is_extension_installed "$uuid"; then
    installed_extension_supports "$uuid" "$version" && return 0
  fi
  if ! info=$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=$uuid&shell_version=$version"); then
    log_warn "$uuid is not available for GNOME Shell $version, skipping it"
    return 1
  fi
  path=$(python3 -c '
import json, sys
info = json.load(sys.stdin)
shells = info.get("shell_version_map")
if shells is not None and sys.argv[1] not in shells:
    sys.exit(3)
print(info["download_url"])
' "$version" <<<"$info") || rc=$?
  if ((rc == 3)); then
    log_warn "$uuid does not support GNOME Shell $version yet, skipping it"
    return 1
  elif ((rc != 0)); then
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
