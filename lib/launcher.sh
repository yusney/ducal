#!/usr/bin/env bash
# Ulauncher: the launcher on Super+Space. A separate app, so it works on every
# GNOME version. Source after lib/common.sh; install_ulauncher also needs lib/apps.sh.

DUCAL_ULAUNCHER_PPA=https://ppa.launchpadcontent.net/agornostal/ulauncher/ubuntu
DUCAL_ULAUNCHER_KEY=59EBDE772980C381CA13FA59FAF1020699503176 # Launchpad PPA for Aleksandr Gornostal

# install_ulauncher — Ulauncher (an app launcher that does not depend on the GNOME
# version) from its PPA, started at every login. Fails without changing apt when
# the PPA cannot be added.
install_ulauncher() {
  local list=/etc/apt/sources.list.d/ulauncher.list key=/etc/apt/keyrings/ulauncher.asc
  if ! is_pkg_installed ulauncher; then
    log_step "Installing Ulauncher"
    as_root install -m 0755 -d /etc/apt/keyrings
    if ! curl -fsSL --retry 2 "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$DUCAL_ULAUNCHER_KEY" |
      as_root tee "$key" >/dev/null; then
      log_warn "Could not get the Ulauncher signing key"
      return 1
    fi
    as_root chmod a+r "$key"
    echo "deb [signed-by=$key] $DUCAL_ULAUNCHER_PPA $(apt_repo_codename "$DUCAL_ULAUNCHER_PPA" Ulauncher) main" |
      as_root tee "$list" >/dev/null
    as_root apt-get update -qq || log_warn "apt-get update failed"
    DUCAL_APT_UPDATED=1
    apt_install ulauncher
    if ! is_pkg_installed ulauncher; then
      as_root rm -f "$list" # a repository that gave nothing must not slow every apt update
      return 1
    fi
  fi
  local settings="$HOME/.config/ulauncher/settings.json"
  if [[ ! -f $settings ]]; then
    mkdir -p "$(dirname "$settings")"
    printf '{\n    "show-indicator-icon": false\n}\n' >"$settings"
  fi
  ulauncher_add_shortcuts || true
  # the current ducal theme's colors (`ducal theme` keeps them in step later)
  (
    # shellcheck source=/dev/null
    source "$DUCAL_ROOT/themes/$(cat "$DUCAL_CONFIG_DIR/current" 2>/dev/null || echo tokyo-night)/palette.env"
    ulauncher_apply_theme
  )
  systemctl --user enable ulauncher.service 2>/dev/null || true
  systemctl --user start ulauncher.service 2>/dev/null || true
}

# ulauncher_add_shortcuts — web searches typed as "KEYWORD query": yt (YouTube) and
# gh (GitHub) with their icons, next to Ulauncher's own g (Google), so (Stack
# Overflow) and wiki. Keeps every shortcut the user has and never adds a keyword
# twice. True when it changed the file (Ulauncher reads it only when it starts).
ulauncher_add_shortcuts() {
  local icons="$HOME/.config/ulauncher/icons"
  mkdir -p "$icons"
  cp "$DUCAL_ROOT"/config/ulauncher/icons/*.svg "$icons/"
  python3 - "$HOME/.config/ulauncher/shortcuts.json" "$icons" <<'EOF'
import json, os, sys, time, uuid

path, icons = sys.argv[1], sys.argv[2]
media = "/usr/share/ulauncher/media/"
if os.path.exists(path):
    with open(path) as f:
        records = json.load(f)
else:
    # Ulauncher's own first-run shortcuts, which it skips once the file exists
    records = {}
    for name, keyword, cmd, icon in [
        ("Google Search", "g", "https://google.com/search?q=%s", "google-search-icon.png"),
        ("Stack Overflow", "so", "https://stackoverflow.com/search?q=%s", "stackoverflow-icon.svg"),
        ("Wikipedia", "wiki", "https://en.wikipedia.org/wiki/%s", "wikipedia-icon.png"),
    ]:
        records[keyword] = {"name": name, "keyword": keyword, "cmd": cmd, "icon": media + icon,
                            "is_default_search": True}

ours = [
    ("YouTube", "yt", "https://www.youtube.com/results?search_query=%s", "youtube.svg"),
    ("GitHub", "gh", "https://github.com/search?q=%s", "github.svg"),
]
changed = False
for name, keyword, cmd, icon in ours:
    icon = os.path.join(icons, icon)
    mine = [r for r in records.values() if r.get("keyword") == keyword]
    if not mine:
        records[keyword] = {"name": name, "keyword": keyword, "cmd": cmd, "icon": icon,
                            "is_default_search": False}
        changed = True
    # shortcuts ducal made before it had icons
    for r in mine:
        if r.get("cmd") == cmd and not r.get("icon"):
            r["icon"] = icon
            changed = True
if not changed and os.path.exists(path):
    sys.exit(1)

result, now = {}, time.time()
for i, record in enumerate(records.values()):
    if "id" not in record:
        record.update(id=str(uuid.uuid4()), run_without_argument=False, added=now + i)
    result[record["id"]] = record
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(result, f, indent=4)
EOF
}

# ulauncher_apply_theme — a Ulauncher theme in the colors of the loaded palette
# (palette.env variables), made the current one. Ulauncher reads it when it starts.
ulauncher_apply_theme() {
  local dir="$HOME/.config/ulauncher/user-themes/ducal"
  mkdir -p "$dir"
  render_template "$DUCAL_ROOT/templates/ulauncher.css" >"$dir/theme.css"
  printf '@import url("theme.css");\n\n.input {\n    caret-color: %s;\n}\n' "$ACCENT" >"$dir/theme-gtk-3.20.css"
  cat >"$dir/manifest.json" <<EOF
{
    "manifest_version": "1",
    "name": "ducal",
    "display_name": "ducal ($NAME)",
    "extend_theme": "light",
    "css_file": "theme.css",
    "css_file_gtk_3.20+": "theme-gtk-3.20.css",
    "matched_text_hl_colors": {
        "when_selected": "$ACCENT",
        "when_not_selected": "$ACCENT"
    }
}
EOF
  python3 - "$HOME/.config/ulauncher/settings.json" <<'EOF'
import json, os, sys
path = sys.argv[1]
settings = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            settings = json.load(f)
    except ValueError:
        settings = {}
settings["theme-name"] = "ducal"
with open(path, "w") as f:
    json.dump(settings, f, indent=4, sort_keys=True)
EOF
  systemctl --user try-restart ulauncher.service 2>/dev/null || true
}
