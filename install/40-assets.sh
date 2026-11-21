#!/usr/bin/env bash
# Module: assets — GTK themes, icons and cursors, then the default theme.
# Third-party assets are downloaded from their upstream projects, never redistributed.
# Sourced by install.sh (DUCAL_ROOT and lib/common.sh are already loaded).

# shellcheck source=../lib/groups.sh
source "$DUCAL_ROOT/lib/groups.sh"
if ! group_on gnome; then
  log_ok "GNOME desktop not chosen, skipping"
  return 0
fi

# shellcheck source=../lib/apps.sh
source "$DUCAL_ROOT/lib/apps.sh"

src_dir="$DUCAL_DATA_DIR/src"
mkdir -p "$src_dir"

# fetch_repo OWNER/REPO — shallow clone into the ducal cache, prints its path.
fetch_repo() {
  local dest
  dest="$src_dir/$(basename "$1")"
  rm -rf "$dest"
  git clone --quiet --depth 1 "https://github.com/$1.git" "$dest" >&2 || die "Could not clone $1"
  echo "$dest"
}

apt_install sassc gtk2-engines-murrine gnome-themes-extra git

# GTK + GNOME Shell themes (GPL-3.0, Fausto-Korpsvart)
if [[ ! -d $HOME/.themes/Tokyonight-Dark ]]; then
  log_step "Installing the Tokyo Night GTK theme"
  repo=$(fetch_repo Fausto-Korpsvart/Tokyonight-GTK-Theme)
  (cd "$repo/themes" && ./install.sh -c dark)
fi
if [[ ! -d $HOME/.themes/Gruvbox-Dark ]]; then
  log_step "Installing the Gruvbox GTK theme"
  repo=$(fetch_repo Fausto-Korpsvart/Gruvbox-GTK-Theme)
  (cd "$repo/themes" && ./install.sh -c dark)
fi
log_ok "GTK themes ready"

# Icons (GPL-3.0, vinceliuice)
if [[ ! -d $HOME/.local/share/icons/Tela-circle-dark ]]; then
  log_step "Installing Tela circle icons"
  repo=$(fetch_repo vinceliuice/Tela-circle-icon-theme)
  (cd "$repo" && ./install.sh)
fi
log_ok "Icons ready"

# Cursors (GPL-3.0, vinceliuice)
if [[ ! -d $HOME/.icons/Vimix-white-cursors ]]; then
  log_step "Installing Vimix cursors"
  repo=$(fetch_repo vinceliuice/Vimix-cursors)
  mkdir -p "$HOME/.icons"
  cp -r "$repo/dist-white" "$HOME/.icons/Vimix-white-cursors"
fi
# Some X11 apps only read the default cursor theme
mkdir -p "$HOME/.icons/default"
printf '[Icon Theme]\nInherits=Vimix-white-cursors\n' >"$HOME/.icons/default/index.theme"
log_ok "Cursors ready"

# First install: apply the default theme. Later runs keep the user's choice.
if [[ ! -f $DUCAL_CONFIG_DIR/current ]]; then
  "$DUCAL_ROOT/bin/ducal" theme tokyo-night
fi
