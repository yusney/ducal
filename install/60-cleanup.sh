#!/usr/bin/env bash
# Module: cleanup — optional removal of preinstalled software. Nothing happens unless chosen.
#   DUCAL_CLEANUP="apps,office,telemetry,services" (or all / none) answers in advance;
#   otherwise the installer asks for each group (none without a terminal).
# Sourced by install.sh (DUCAL_ROOT and lib/common.sh are already loaded).

# shellcheck source=../lib/apps.sh
source "$DUCAL_ROOT/lib/apps.sh"
# shellcheck source=../lib/cleanup.sh
source "$DUCAL_ROOT/lib/cleanup.sh"

groups=$(select_cleanup) || exit 1
if [[ -z $groups ]]; then
  log_ok "No cleanup selected"
  return 0
fi
for group in $groups; do
  "cleanup_$group"
  log_ok "Cleanup done: $group"
done
