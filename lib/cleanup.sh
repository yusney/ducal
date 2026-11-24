#!/usr/bin/env bash
# Optional cleanup of preinstalled Ubuntu software. Source after lib/common.sh and lib/apps.sh.
# Packages are removed with `apt-get remove` (not purge, no autoremove): settings and
# documents in your home folder are kept, and `sudo apt install <package>` brings
# any of them back. Services are only disabled, never uninstalled.

DUCAL_CLEANUP_GROUPS=(apps office telemetry services)

# Apps the ducal setup replaces or most developers do not need
CLEANUP_APPS=(
  rhythmbox totem showtime shotwell gnome-snapshot     # media (showtime: video on 25.10+)
  transmission-gtk remmina gnome-clocks gnome-characters # utilities
  yelp usb-creator-gtk simple-scan deja-dup gnome-calendar
  gedit gnome-text-editor                              # replaced by Neovim / VS Code
)
CLEANUP_OFFICE=(libreoffice-common libreoffice-core thunderbird)
CLEANUP_TELEMETRY=(ubuntu-report ubuntu-insights apport whoopsie kerneloops) # ubuntu-insights: 25.10+

# System units disabled by the services group
CLEANUP_SYSTEM_UNITS=(
  cups.service cups.socket cups.path cups-browsed.service # printing
  ModemManager.service                                    # 3G/4G modems
  avahi-daemon.service avahi-daemon.socket                # network discovery
)
# File indexing: tracker on 24.04, renamed localsearch on GNOME 47+ (Ubuntu 24.10+)
CLEANUP_USER_UNITS=(tracker-miner-fs-3.service localsearch-3.service)

cleanup_group_description() {
  case $1 in
    apps) echo "Remove apps you probably do not need (music, video, photos, torrents, remote desktop, clocks, text editors...)" ;;
    office) echo "Remove LibreOffice and Thunderbird (including the Thunderbird snap)" ;;
    telemetry) echo "Remove usage statistics and crash reporting (ubuntu-report, ubuntu-insights, apport, whoopsie, kerneloops)" ;;
    services) echo "Disable file indexing, printing, mobile modems and network discovery (not uninstalled)" ;;
  esac
}

# protect_desktop PKG_TO_REMOVE... — removing a default app also removes the
# ubuntu-desktop metapackages. Mark everything they keep installed as manual
# first, so a later `apt autoremove` never takes the rest of the desktop with it.
protect_desktop() {
  local keep=() dep
  while read -r dep; do
    [[ " $* " == *" $dep "* ]] && continue
    is_pkg_installed "$dep" && keep+=("$dep")
  # LC_ALL=C: apt-cache translates "Depends:" into the system language
  done < <(LC_ALL=C apt-cache depends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances \
    ubuntu-desktop ubuntu-desktop-minimal 2>/dev/null |
    awk '/^ *\|?(Depends|Recommends):/ && $2 !~ /^</ {print $2}' | sort -u)
  [[ ${#keep[@]} -eq 0 ]] && return 0
  as_root apt-mark manual "${keep[@]}" >/dev/null
}

# apt_remove PKG... — removes only the packages that are installed.
apt_remove() {
  local present=() p
  for p in "$@"; do is_pkg_installed "$p" && present+=("$p"); done
  [[ ${#present[@]} -eq 0 ]] && return 0
  protect_desktop "${present[@]}"
  log_step "apt: removing ${present[*]}"
  as_root env DEBIAN_FRONTEND=noninteractive apt-get remove -y "${present[@]}"
}

cleanup_apps() { apt_remove "${CLEANUP_APPS[@]}"; }

cleanup_office() {
  apt_remove "${CLEANUP_OFFICE[@]}"
  # On Ubuntu the thunderbird deb is a bridge to the snap; remove the snap too
  local snaps
  snaps=$(snap list 2>/dev/null | awk '{print $1}') || true
  if grep -qx thunderbird <<<"$snaps"; then
    as_root snap remove thunderbird
  fi
}

cleanup_telemetry() { apt_remove "${CLEANUP_TELEMETRY[@]}"; }

# One unit at a time: a unit that is not installed must not keep the others running.
cleanup_services() {
  local unit
  for unit in "${CLEANUP_SYSTEM_UNITS[@]}"; do
    as_root systemctl disable --now "$unit" 2>/dev/null || log_warn "Skipped $unit (not installed or already off)"
  done
  for unit in "${CLEANUP_USER_UNITS[@]}"; do
    # mask would accept a unit this release does not have: skip those
    systemctl --user list-unit-files "$unit" >/dev/null 2>&1 || continue
    systemctl --user mask --now "$unit" 2>/dev/null || log_warn "Could not disable $unit (run the installer as your user, not root)"
  done
}

cleanup_restore_services() {
  local unit failed=0
  for unit in "${CLEANUP_SYSTEM_UNITS[@]}"; do
    as_root systemctl enable --now "$unit" 2>/dev/null || { log_warn "Could not enable $unit"; failed=1; }
  done
  for unit in "${CLEANUP_USER_UNITS[@]}"; do
    systemctl --user unmask "$unit" 2>/dev/null || { log_warn "Could not unmask $unit"; failed=1; }
  done
  if [[ $failed -ne 0 ]]; then
    log_error "Some services could not be enabled; see the messages above"
    return 1
  fi
  log_ok "Services enabled again"
}

# parse_cleanup "apps,office" | all | none -> space-separated validated groups
parse_cleanup() {
  local input=${1// /} name out=()
  case $input in
    all) echo "${DUCAL_CLEANUP_GROUPS[*]}"; return 0 ;;
    none | "") echo ""; return 0 ;;
  esac
  IFS=',' read -ra names <<<"$input"
  for name in "${names[@]}"; do
    [[ " ${DUCAL_CLEANUP_GROUPS[*]} " == *" $name "* ]] || die "Unknown cleanup group: $name (available: ${DUCAL_CLEANUP_GROUPS[*]})"
    out+=("$name")
  done
  echo "${out[*]}"
}

# select_cleanup — from $DUCAL_CLEANUP, else ask on a terminal, else nothing.
select_cleanup() {
  if [[ -n ${DUCAL_CLEANUP:-} ]]; then parse_cleanup "$DUCAL_CLEANUP"; return; fi
  if [[ ! -t 0 ]]; then echo ""; return; fi
  local chosen=() group answer
  for group in "${DUCAL_CLEANUP_GROUPS[@]}"; do
    read -r -p "$(cleanup_group_description "$group")? [y/N] " answer </dev/tty || answer=no
    [[ ${answer,,} == y ]] && chosen+=("$group")
  done
  echo "${chosen[*]}"
}
