#!/usr/bin/env bash
# Install groups: what each person chooses to install, by area.
#   DUCAL_GROUPS="terminal,languages"   pick groups in advance (or all / none)
#   DUCAL_PROFILE=desktop|dev           pick a preset of groups
#   DUCAL_WSL=1|0                       force WSL detection on or off
# Sourced after lib/common.sh.

# Canonical order: modules install in this order whatever order they are given in.
DUCAL_GROUPS_ALL=(terminal languages desktop-apps gnome system cleanup)
# WSL has no graphical session, so only these groups make sense there.
DUCAL_GROUPS_HEADLESS=(terminal languages)

declare -A DUCAL_GROUP_LABEL=(
  [terminal]="Terminal and programming: fish, Neovim, git, gh, Claude Code (status line, plugins, MCP), gentle-ai, opencode..."
  [languages]="Languages: Node.js, Go, Rust, Docker (you pick which)"
  [desktop-apps]="Desktop apps: kitty, Nerd Font, Chrome, VS Code... (you pick which)"
  [gnome]="GNOME desktop: extensions, tiling, themes, icons, wallpapers, shortcuts"
  [system]="Login screen and boot splash with the ducal mark (system files)"
  [cleanup]="Cleanup: remove preinstalled software you do not need"
)

# Optional items inside a group, installed by install_extra_<item>
declare -A DUCAL_GROUP_ITEMS=(
  [languages]="node go rust docker"
  [desktop-apps]="chrome code steam discord"
)
declare -A DUCAL_ITEM_LABEL=(
  [node]="Node.js LTS (fnm) and the Claude Code status line"
  [go]="Go"
  [rust]="Rust (rustup)"
  [docker]="Docker Engine"
  [chrome]="Google Chrome"
  [code]="Visual Studio Code"
  [steam]="Steam"
  [discord]="Discord"
)

is_wsl() {
  case ${DUCAL_WSL:-} in
    1) return 0 ;;
    0) return 1 ;;
  esac
  [[ -n ${WSL_DISTRO_NAME:-} ]] || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null
}

available_groups() {
  if is_wsl; then echo "${DUCAL_GROUPS_HEADLESS[*]}"; else echo "${DUCAL_GROUPS_ALL[*]}"; fi
}

default_profile() { if is_wsl; then echo dev; else echo desktop; fi; }

# profile_groups NAME -> its groups
profile_groups() {
  case $1 in
    desktop) echo "terminal desktop-apps gnome" ;;
    dev) echo "terminal languages" ;;
    *) die "Unknown profile: $1 (available: desktop dev)" ;;
  esac
}

# parse_groups "gnome, terminal" | all | none -> validated groups in canonical order.
# On WSL, graphical groups are dropped with a warning.
parse_groups() {
  local input=${1//,/ } name wanted=() out=() available
  available=" $(available_groups) "
  case ${input// /} in
    all) available_groups; return 0 ;;
    none | "") echo ""; return 0 ;;
  esac
  for name in $input; do
    [[ " ${DUCAL_GROUPS_ALL[*]} " == *" $name "* ]] || die "Unknown group: $name (available: ${DUCAL_GROUPS_ALL[*]})"
    if [[ $available != *" $name "* ]]; then
      log_warn "$name is not available on WSL, skipping it"
      continue
    fi
    wanted+=("$name")
  done
  for name in "${DUCAL_GROUPS_ALL[@]}"; do
    [[ " ${wanted[*]} " == *" $name "* ]] && out+=("$name")
  done
  echo "${out[*]}"
}

use_whiptail() { [[ -z ${DUCAL_NO_WHIPTAIL:-} ]] && has_cmd whiptail; }

# checklist TITLE TEXT "TAG|LABEL|on/off"... -> chosen tags; fails when cancelled.
# The first entry, "all", ticks every entry at once.
# Without whiptail, asks one y/N question per entry on stdin.
checklist() {
  local title=$1 text=$2 entry tag label state answer args=() chosen=() every=()
  shift 2
  for entry in "$@"; do every+=("${entry%%|*}"); done
  if use_whiptail; then
    args=(all "Everything below" OFF)
    for entry in "$@"; do
      IFS='|' read -r tag label state <<<"$entry"
      args+=("$tag" "$label" "$state")
    done
    # whiptail draws on the terminal and prints the choice on stderr
    answer=$(whiptail --title "$title" --separate-output --checklist "$text" 20 90 $(($# + 1)) "${args[@]}" 3>&1 1>&2 2>&3) || return 1
    # one tag per line (--separate-output); some versions quote them
    answer=$(echo $answer | tr -d '"')
    if [[ " $answer " == *" all "* ]]; then echo "${every[*]}"; else echo "$answer"; fi
    return 0
  fi
  echo "$title: $text" >&2
  read -r -p "  Everything below? [y/N] " answer || answer=""
  if [[ ${answer,,} == y ]]; then
    echo "${every[*]}"
    return 0
  fi
  for entry in "$@"; do
    IFS='|' read -r tag label state <<<"$entry"
    if [[ $state == ON ]]; then
      read -r -p "  $label [Y/n] " answer || answer=""
      [[ ${answer,,} == n ]] || chosen+=("$tag")
    else
      read -r -p "  $label [y/N] " answer || answer=""
      [[ ${answer,,} == y ]] && chosen+=("$tag")
    fi
  done
  echo "${chosen[*]}"
}

# menu_groups — asks which groups to install, the default profile ticked.
menu_groups() {
  local name defaults entries=() text="Space ticks a group, Enter confirms."
  defaults=" $(profile_groups "$(default_profile)") "
  is_wsl && text="WSL detected: only the terminal groups are offered. $text"
  for name in $(available_groups); do
    if [[ $defaults == *" $name "* ]]; then
      entries+=("$name|${DUCAL_GROUP_LABEL[$name]}|ON")
    else
      entries+=("$name|${DUCAL_GROUP_LABEL[$name]}|OFF")
    fi
  done
  checklist "ducal: what to install" "$text" "${entries[@]}"
}

# menu_items GROUP — asks which optional items of GROUP to install.
menu_items() {
  local item entries=()
  for item in ${DUCAL_GROUP_ITEMS[$1]}; do entries+=("$item|${DUCAL_ITEM_LABEL[$item]}|OFF"); done
  checklist "ducal: $1" "Pick the ones you want." "${entries[@]}"
}

# resolve_groups — DUCAL_GROUPS, else DUCAL_PROFILE, else the menu on a terminal,
# else the default profile.
resolve_groups() {
  local input
  if [[ -n ${DUCAL_GROUPS:-} ]]; then
    input=$DUCAL_GROUPS
  elif [[ -n ${DUCAL_PROFILE:-} ]]; then
    input=$(profile_groups "$DUCAL_PROFILE") || return 1
  elif [[ -t 0 ]]; then
    input=$(menu_groups) || return 1
  else
    input=$(profile_groups "$(default_profile)")
  fi
  parse_groups "$input"
}

# group_on NAME — whether NAME was chosen. Without a choice (a module run on
# its own with --only), every group is on, as before groups existed.
group_on() { [[ -z ${DUCAL_GROUPS_SELECTED+x} || " $DUCAL_GROUPS_SELECTED " == *" $1 "* ]]; }

# drop_desktop_items "chrome,go" | all -> the items WSL can install, with a warning for the rest
drop_desktop_items() {
  local input=${1// /} item out=()
  [[ $input == all ]] && input=${DUCAL_GROUP_ITEMS[languages]// /,}
  [[ $input == none ]] && { echo none; return 0; }
  IFS=',' read -ra names <<<"$input"
  for item in "${names[@]}"; do
    if [[ " ${DUCAL_GROUP_ITEMS[desktop-apps]} " == *" $item "* ]]; then
      log_warn "$item is not available on WSL, skipping it"
      continue
    fi
    out+=("$item")
  done
  input=$(IFS=,; echo "${out[*]}")
  echo "${input:-none}"
}

# select_install — resolves the groups once and the answers every module reads:
# DUCAL_GROUPS_SELECTED, DUCAL_EXTRAS (items of the chosen groups), DUCAL_SYSTEM
# (choosing the group is the consent) and DUCAL_CLEANUP (none unless chosen).
# Answers already set in the environment win.
select_install() {
  local g picked items=() extra=""
  DUCAL_GROUPS_SELECTED=$(resolve_groups) || return 1
  # An explicit answer turns its group on, as it did before groups existed
  [[ ${DUCAL_SYSTEM:-} == yes ]] && extra+=" system"
  [[ -n ${DUCAL_CLEANUP:-} && $DUCAL_CLEANUP != none ]] && extra+=" cleanup"
  if [[ -n $extra ]]; then
    DUCAL_GROUPS_SELECTED=$(parse_groups "$DUCAL_GROUPS_SELECTED$extra") || return 1
  fi
  export DUCAL_GROUPS_SELECTED
  if [[ -n ${DUCAL_EXTRAS:-} ]] && is_wsl; then
    export DUCAL_EXTRAS
    DUCAL_EXTRAS=$(drop_desktop_items "$DUCAL_EXTRAS")
  elif [[ -z ${DUCAL_EXTRAS:-} ]]; then
    for g in languages desktop-apps; do
      group_on "$g" || continue
      [[ -t 0 || -n ${DUCAL_ASK_ITEMS:-} ]] || continue
      picked=$(menu_items "$g") || return 1
      # shellcheck disable=SC2206 # space-separated item names
      items+=($picked)
    done
    DUCAL_EXTRAS=$(IFS=,; echo "${items[*]}")
    export DUCAL_EXTRAS=${DUCAL_EXTRAS:-none}
  fi
  if group_on system; then export DUCAL_SYSTEM=${DUCAL_SYSTEM:-yes}; else export DUCAL_SYSTEM=no; fi
  group_on cleanup || export DUCAL_CLEANUP=none
  return 0
}
