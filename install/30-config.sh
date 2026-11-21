#!/usr/bin/env bash
# Module: config — links the ducal configuration files and the `ducal` command.
# Sourced by install.sh (DUCAL_ROOT and lib/common.sh are already loaded).

# shellcheck source=../lib/groups.sh
source "$DUCAL_ROOT/lib/groups.sh"

cfg="$DUCAL_ROOT/config"

# Files nothing rewrites at runtime: symlink them so `git pull` updates them.
# Files that btop and `ducal theme` rewrite: copy them once.
if group_on terminal; then
  link_file "$cfg/fish/config.fish" "$HOME/.config/fish/config.fish"
  link_file "$cfg/nvim" "$HOME/.config/nvim"
  seed_file "$cfg/btop/btop.conf" "$HOME/.config/btop/btop.conf"
  log_ok "Linked fish and Neovim configuration, seeded btop"
fi
if group_on desktop-apps; then
  link_file "$cfg/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
  log_ok "Linked kitty configuration"
fi
if group_on gnome; then
  seed_file "$cfg/gtk-4.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"
  log_ok "Seeded GTK 4 configuration"
fi

link_file "$DUCAL_ROOT/bin/ducal" "$HOME/.local/bin/ducal"
mkdir -p "$DUCAL_CONFIG_DIR"
log_ok "Installed the ducal command in ~/.local/bin"

# Claude Code status line (Tokyo Night powerline). Only when ccstatusline is
# installed (node extra); an existing status line in Claude's settings is kept.
if group_on terminal && { has_cmd ccstatusline || [[ -x $HOME/.local/share/fnm/aliases/default/bin/ccstatusline ]]; }; then
  seed_file "$cfg/ccstatusline/settings.json" "$HOME/.config/ccstatusline/settings.json"
  mkdir -p "$HOME/.claude"
  python3 - "$HOME/.claude/settings.json" <<'PY'
import json, os, sys
path = sys.argv[1]
settings = {}
if os.path.exists(path):
    with open(path) as f:
        settings = json.load(f)
if "statusLine" not in settings:
    settings["statusLine"] = {"type": "command", "command": "ccstatusline", "padding": 0, "refreshInterval": 10}
    with open(path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
PY
  log_ok "Claude Code status line ready"
fi

# The assets module applies the default theme once the GTK themes are in place;
# without the GNOME group, apply it here so the terminal gets its colors.
if ! group_on gnome && [[ ! -f $DUCAL_CONFIG_DIR/current ]]; then
  "$DUCAL_ROOT/bin/ducal" theme tokyo-night
fi
