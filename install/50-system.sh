#!/usr/bin/env bash
# Module: system — themed login screen (GDM) and boot splash (Plymouth). Optional.
#   DUCAL_SYSTEM=yes|no   answer the confirmation in advance (default: ask; no without a terminal)
#   DUCAL_LOGO=/path.svg  your own logo instead of the ducal mark (shown with the distribution name and version)
# Undo at any time with: ducal system restore
# Sourced by install.sh (DUCAL_ROOT and lib/common.sh are already loaded).

# shellcheck source=../lib/groups.sh
source "$DUCAL_ROOT/lib/groups.sh"
if ! group_on system; then
  log_ok "Login screen and boot splash not chosen, skipping"
  return 0
fi

# shellcheck source=../lib/system.sh
source "$DUCAL_ROOT/lib/system.sh"

answer=${DUCAL_SYSTEM:-}
if [[ -z $answer ]]; then
  if [[ -t 0 ]]; then
    read -r -p "Theme the login screen and boot splash? This changes system files (undo: ducal system restore) [y/N] " answer ||
      answer=no # Ctrl-D counts as "no"
  else
    answer=no
  fi
fi
if [[ ${answer,,} != y && ${answer,,} != yes ]]; then
  log_ok "Skipped the login screen and boot splash"
  return 0
fi

theme=$(cat "$DUCAL_CONFIG_DIR/current" 2>/dev/null || echo tokyo-night)
# shellcheck source=/dev/null
source "$DUCAL_ROOT/themes/$theme/palette.env"
system_install "${DUCAL_LOGO:-}"
