#!/usr/bin/env bash
# Preflight: checks the system before the installer changes anything, installs
# what the installer itself needs, and stops with a clear reason otherwise.
# Sourced after lib/common.sh and lib/groups.sh.

# shellcheck source=apps.sh
source "$DUCAL_ROOT/lib/apps.sh"

# What the installer needs before any module runs (whiptail draws the menus)
DUCAL_PREREQUISITES=(curl git python3 ca-certificates whiptail)
DUCAL_MIN_FREE_GB=5

no_internet() { die "No internet connection (github.com is unreachable): ducal downloads its apps and themes"; }

# preflight_system — run before the menu.
preflight_system() {
  log_step "Checking your system"

  has_cmd apt-get || die "ducal needs Ubuntu (or another system with apt): apt-get not found"

  local arch
  arch=$(uname -m)
  [[ $arch == x86_64 ]] || die "ducal supports x86_64 only (this machine is $arch): several apps have no other build"

  [[ $(id -u) -ne 0 ]] || die "Run the installer as your user, not as root: it asks for sudo when it needs it"

  local os_release="${DUCAL_SYSROOT:-}/etc/os-release" id="" version="" name
  if [[ -f $os_release ]]; then
    id=$(sed -n 's/^ID=//p' "$os_release" | tr -d '"')
    version=$(sed -n 's/^VERSION_ID=//p' "$os_release" | tr -d '"')
  fi
  name="${id:-unknown} ${version}"
  name=${name^}
  if [[ $id != ubuntu ]]; then
    log_warn "ducal targets Ubuntu, this is $name: continuing, but expect surprises"
  elif [[ $version != 24.04 ]]; then
    log_warn "Ubuntu $version is untested (ducal targets 24.04): continuing anyway"
  fi
  log_ok "System: ${name% } $arch"

  has_cmd sudo || die "sudo not found: install it, or ask an administrator to give your user sudo access"
  sudo -v || die "Your user cannot use sudo: ducal needs it to install packages"
  log_ok "sudo works"

  # Before installing anything: without curl yet, bash's own /dev/tcp checks the connection
  if has_cmd curl; then
    curl -fsS --max-time 10 -o /dev/null https://github.com || no_internet
  else
    timeout 10 bash -c 'exec 3<>/dev/tcp/github.com/443' 2>/dev/null || no_internet
  fi
  log_ok "Internet connection"

  local missing=() p
  for p in "${DUCAL_PREREQUISITES[@]}"; do is_pkg_installed "$p" || missing+=("$p"); done
  if [[ ${#missing[@]} -gt 0 ]]; then
    as_root apt-get update -qq || die "apt-get update failed: check your connection and apt sources"
    apt_install "${missing[@]}" || die "Could not install ${missing[*]}"
  fi
  log_ok "Prerequisites ready: ${DUCAL_PREREQUISITES[*]}"

  local free_kb
  # only a warning: a failing df must not stop the install
  free_kb=$(df -Pk "$HOME" 2>/dev/null | awk 'NR == 2 { print $4 }') || free_kb=""
  if [[ -n $free_kb ]] && ((free_kb < DUCAL_MIN_FREE_GB * 1024 * 1024)); then
    log_warn "Less than ${DUCAL_MIN_FREE_GB} GB free in $HOME: the install may run out of space"
  fi
}

# preflight_groups — run after the menu, with DUCAL_GROUPS_SELECTED set.
preflight_groups() {
  if { group_on gnome || group_on system; } && { [[ -n ${DUCAL_NO_GNOME:-} ]] || ! has_cmd gnome-shell; }; then
    die "GNOME Shell not found: the gnome and system groups need a GNOME desktop. Run again without them, for example: ./install.sh --profile dev"
  fi
  return 0
}
