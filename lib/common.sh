#!/usr/bin/env bash
# Shared helpers for ducal scripts. Source it; do not execute it.

DUCAL_ROOT=${DUCAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
DUCAL_CONFIG_DIR=${DUCAL_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/ducal}
DUCAL_DATA_DIR=${DUCAL_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/ducal}

if [[ -t 1 ]]; then
  _c_blue=$'\e[34m' _c_green=$'\e[32m' _c_yellow=$'\e[33m' _c_red=$'\e[31m' _c_reset=$'\e[0m'
else
  _c_blue='' _c_green='' _c_yellow='' _c_red='' _c_reset=''
fi

log_step() { printf '%s==>%s %s\n' "$_c_blue" "$_c_reset" "$*"; }
log_ok() { printf '%s  ✓%s %s\n' "$_c_green" "$_c_reset" "$*"; }
log_warn() { printf '%s  !%s %s\n' "$_c_yellow" "$_c_reset" "$*" >&2; }
log_error() { printf '%s  ✗%s %s\n' "$_c_red" "$_c_reset" "$*" >&2; }
die() { log_error "$*"; exit 1; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# link_file SOURCE DEST
# Symlinks DEST to SOURCE. An existing DEST that is not already that link is
# moved to DEST.ducal-backup-<timestamp> first, so nothing is lost.
link_file() {
  local src=$1 dest=$2
  [[ -e $src ]] || die "link_file: source does not exist: $src"
  mkdir -p "$(dirname "$dest")"
  if [[ -L $dest && $(readlink "$dest") == "$src" ]]; then
    return 0
  fi
  if [[ -e $dest || -L $dest ]]; then
    local backup
    backup="$dest.ducal-backup-$(date +%Y%m%d-%H%M%S)"
    mv "$dest" "$backup"
    log_warn "Backed up existing $dest to $backup"
  fi
  ln -s "$src" "$dest"
}

# seed_file SOURCE DEST
# Copies SOURCE to DEST only when DEST does not exist yet. Use it for files that
# programs rewrite at runtime (a symlink would let them modify the repository).
seed_file() {
  local src=$1 dest=$2
  [[ -e $dest ]] && return 0
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
}

# hex_to_rgba_tuple "#7aa2f7" [alpha] -> "(0.478, 0.635, 0.969, 1.0)"
# LC_ALL=C forces "." as the decimal separator on any system locale.
hex_to_rgba_tuple() {
  local hex=${1#\#} alpha=${2:-1.0}
  [[ $hex =~ ^[0-9a-fA-F]{6}$ ]] || die "Invalid hex color: $1"
  LC_ALL=C awk -v r=$((16#${hex:0:2})) -v g=$((16#${hex:2:2})) -v b=$((16#${hex:4:2})) -v a="$alpha" \
    'BEGIN { printf "(%.3f, %.3f, %.3f, %s)", r/255, g/255, b/255, a }'
}

# render_template FILE — prints FILE with {{VAR}} placeholders replaced by the
# palette variables loaded from a theme's palette.env.
render_template() {
  sed -e "s|{{NAME}}|$NAME|g" -e "s|{{BG_RGB}}|$BG_RGB|g" -e "s|{{BG_ALT}}|$BG_ALT|g" \
    -e "s|{{BG_HOVER}}|$BG_HOVER|g" -e "s|{{BG}}|$BG|g" -e "s|{{FG_DIM}}|$FG_DIM|g" \
    -e "s|{{FG}}|$FG|g" -e "s|{{MUTED}}|$MUTED|g" -e "s|{{BORDER}}|$BORDER|g" \
    -e "s|{{ACCENT}}|$ACCENT|g" "$1"
}

# Run a command with sudo only when not already root.
as_root() {
  if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi
}
