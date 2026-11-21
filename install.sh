#!/usr/bin/env bash
# ducal installer: turns a fresh Ubuntu into the ducal desktop.
#   ./install.sh              run every module in order
#   ./install.sh --list       list modules
#   ./install.sh --only NAME  run a single module (e.g. --only config)
# Every module is idempotent: running the installer again is safe.
set -euo pipefail

DUCAL_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export DUCAL_ROOT
# shellcheck source=lib/common.sh
source "$DUCAL_ROOT/lib/common.sh"

modules() { find "$DUCAL_ROOT/install" -maxdepth 1 -name '[0-9][0-9]-*.sh' | sort; }
module_name() { basename "$1" .sh | sed -E 's/^[0-9]+-//'; }

usage() {
  sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
}

run_module() {
  local file=$1
  log_step "Module: $(module_name "$file")"
  # shellcheck source=/dev/null
  (source "$file")
}

main() {
  case ${1:-} in
    -h | --help) usage ;;
    --list)
      while read -r f; do module_name "$f"; done < <(modules)
      ;;
    --only)
      [[ -n ${2:-} ]] || die "--only needs a module name (see --list)"
      local match
      match=$(modules | while read -r f; do [[ $(module_name "$f") == "$2" ]] && echo "$f"; done)
      [[ -n $match ]] || die "Unknown module: $2 (see --list)"
      run_module "$match"
      ;;
    "")
      [[ -f /etc/os-release ]] && grep -q '^ID=ubuntu' /etc/os-release ||
        log_warn "ducal targets Ubuntu; continuing anyway"
      while read -r f; do run_module "$f"; done < <(modules)
      log_step "Done. Log out and back in to load every change."
      ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
