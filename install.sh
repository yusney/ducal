#!/usr/bin/env bash
# ducal installer: turns a fresh Ubuntu into the ducal desktop.
#   ./install.sh                 asks what to install (a checklist of groups), then installs it
#   ./install.sh --profile NAME  installs a preset: desktop (the full desktop) or dev (terminal only, WSL)
#   ./install.sh --list          list modules
#   ./install.sh --only NAME     run a single module (e.g. --only config)
# Answer in advance with DUCAL_GROUPS=terminal,languages,desktop-apps,gnome,system,cleanup.
# Every module is idempotent: running the installer again is safe.
set -euo pipefail

DUCAL_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export DUCAL_ROOT
# shellcheck source=lib/common.sh
source "$DUCAL_ROOT/lib/common.sh"
# shellcheck source=lib/groups.sh
source "$DUCAL_ROOT/lib/groups.sh"
# shellcheck source=lib/preflight.sh
source "$DUCAL_ROOT/lib/preflight.sh"

modules() { find "$DUCAL_ROOT/install" -maxdepth 1 -name '[0-9][0-9]-*.sh' | sort; }
module_name() { basename "$1" .sh | sed -E 's/^[0-9]+-//'; }

usage() {
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
}

run_module() {
  local file=$1
  log_step "Module: $(module_name "$file")"
  # shellcheck source=/dev/null
  (source "$file")
}

main() {
  if [[ ${1:-} == --profile ]]; then
    [[ -n ${2:-} ]] || die "--profile needs a name: desktop or dev"
    profile_groups "$2" >/dev/null
    export DUCAL_PROFILE=$2
    shift 2
  fi
  case ${1:-} in
    -h | --help) usage ;;
    --list)
      while read -r f; do module_name "$f"; done < <(modules)
      ;;
    --only)
      [[ -n ${2:-} ]] || die "--only needs a module name (see --list)"
      local match
      match=$(modules | while read -r f; do
        if [[ $(module_name "$f") == "$2" ]]; then echo "$f"; fi
      done)
      [[ -n $match ]] || die "Unknown module: $2 (see --list)"
      run_module "$match"
      ;;
    "")
      preflight_system
      select_install || die "Nothing installed"
      preflight_groups
      log_step "Installing: ${DUCAL_GROUPS_SELECTED:-nothing}"
      while read -r f; do run_module "$f"; done < <(modules)
      log_step "Done. Log out and back in to load every change."
      ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
