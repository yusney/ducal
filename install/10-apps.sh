#!/usr/bin/env bash
# Module: apps — base applications, then the optional extras.
# Extras: set DUCAL_EXTRAS="chrome,code,docker,go,rust,node,steam,discord" (or all / none)
# to skip the questions; otherwise the installer asks for each one.
# Sourced by install.sh (DUCAL_ROOT and lib/common.sh are already loaded).

# shellcheck source=../lib/apps.sh
source "$DUCAL_ROOT/lib/apps.sh"

install_base
log_ok "Base apps ready: kitty, fish, Neovim, Starship, btop, lazygit, yazi, git, gh, Claude Code CLI, JetBrainsMono Nerd Font"

extras=$(select_extras) || exit 1
for extra in $extras; do
  "install_extra_$extra"
  log_ok "Extra ready: $extra"
done
