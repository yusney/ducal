#!/usr/bin/env bash
# Module: apps — base applications, then the optional extras.
# Extras: set DUCAL_EXTRAS="chrome,code,docker,go,rust,node,steam,discord" (or all / none)
# to skip the questions; otherwise the installer asks for each one.
# Sourced by install.sh (DUCAL_ROOT and lib/common.sh are already loaded).

# shellcheck source=../lib/apps.sh
source "$DUCAL_ROOT/lib/apps.sh"
# shellcheck source=../lib/groups.sh
source "$DUCAL_ROOT/lib/groups.sh"

if group_on terminal; then
  install_terminal_tools
  log_ok "Terminal tools ready: fish, Neovim, Starship, btop, lazygit, yazi, git, gh, Claude Code CLI, opencode"
fi
if group_on desktop-apps; then
  install_desktop_apps
  log_ok "Desktop apps ready: kitty, JetBrainsMono Nerd Font"
fi

extras=$(select_extras) || exit 1
for extra in $extras; do
  "install_extra_$extra"
  log_ok "Extra ready: $extra"
done
