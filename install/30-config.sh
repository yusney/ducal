#!/usr/bin/env bash
# Module: config — links the ducal configuration files and the `ducal` command.
# Sourced by install.sh (DUCAL_ROOT and lib/common.sh are already loaded).

cfg="$DUCAL_ROOT/config"

# Files nothing rewrites at runtime: symlink them so `git pull` updates them.
link_file "$cfg/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
link_file "$cfg/fish/config.fish" "$HOME/.config/fish/config.fish"
link_file "$cfg/nvim" "$HOME/.config/nvim"
log_ok "Linked kitty, fish and Neovim configuration"

# Files that btop and `ducal theme` rewrite: copy them once.
seed_file "$cfg/btop/btop.conf" "$HOME/.config/btop/btop.conf"
seed_file "$cfg/gtk-4.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"
log_ok "Seeded btop and GTK 4 configuration"

link_file "$DUCAL_ROOT/bin/ducal" "$HOME/.local/bin/ducal"
mkdir -p "$DUCAL_CONFIG_DIR"
log_ok "Installed the ducal command in ~/.local/bin"
