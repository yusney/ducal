#!/usr/bin/env bash
# Test runner for ducal. Every test runs against a throwaway HOME with stubbed
# desktop commands (gsettings, dconf, pkill), so it never touches the real system.
#   tests/run.sh
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PASS=0 FAIL=0 CURRENT=""

setup_sandbox() {
  SANDBOX=$(mktemp -d)
  export HOME="$SANDBOX/home" STUB_LOG="$SANDBOX/calls.log"
  unset XDG_CONFIG_HOME XDG_DATA_HOME DUCAL_CONFIG_DIR DUCAL_DATA_DIR DUCAL_ROOT
  # the web search lock lives here: keep it away from the real session
  export XDG_RUNTIME_DIR="$SANDBOX/run"
  mkdir -p "$HOME" "$SANDBOX/stubs" "$XDG_RUNTIME_DIR"
  for cmd in gsettings dconf pkill gnome-extensions; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "$STUB_LOG"\n' "$cmd" > "$SANDBOX/stubs/$cmd"
    chmod +x "$SANDBOX/stubs/$cmd"
  done
  export PATH="$SANDBOX/stubs:$ORIG_PATH"
  : > "$STUB_LOG"
}

teardown_sandbox() { rm -rf "$SANDBOX"; }

fail() { echo "    FAIL [$CURRENT]: $*"; FAIL_THIS=1; }
assert_eq() { [[ $1 == "$2" ]] || fail "expected '$2', got '$1'${3:+ ($3)}"; }
assert_contains() { grep -qF -- "$2" "$1" 2>/dev/null || fail "'$1' does not contain '$2'"; }
assert_not_contains() { ! grep -qF -- "$2" "$1" 2>/dev/null || fail "'$1' should not contain '$2'"; }
assert_link() { [[ $(readlink "$1") == "$2" ]] || fail "$1 -> '$(readlink "$1")', expected '$2'"; }

run_test() {
  CURRENT=$1 FAIL_THIS=0
  setup_sandbox
  "$1"
  teardown_sandbox
  if [[ $FAIL_THIS -eq 0 ]]; then PASS=$((PASS + 1)); echo "  ok   $1"; else FAIL=$((FAIL + 1)); echo "  FAIL $1"; fi
}

# ---------------------------------------------------------------- helpers
test_hex_to_rgba_uses_dot_decimal_on_any_locale() {
  local out
  out=$(LC_ALL=es_ES.UTF-8 bash -c "source '$ROOT/lib/common.sh'; hex_to_rgba_tuple '#7aa2f7' 0.95")
  assert_eq "$out" "(0.478, 0.635, 0.969, 0.95)"
}

test_link_file_backs_up_existing_file_and_is_idempotent() {
  source "$ROOT/lib/common.sh"
  echo src > "$SANDBOX/src"; echo old > "$HOME/dest"
  link_file "$SANDBOX/src" "$HOME/dest" 2>/dev/null
  link_file "$SANDBOX/src" "$HOME/dest" 2>/dev/null
  assert_link "$HOME/dest" "$SANDBOX/src"
  assert_eq "$(ls "$HOME" | grep -c 'dest.ducal-backup-')" "1" "exactly one backup"
  assert_eq "$(cat "$HOME"/dest.ducal-backup-*)" "old"
}

# ---------------------------------------------------------------- ducal theme
test_theme_without_args_lists_themes() {
  local out
  out=$("$ROOT/bin/ducal" theme); local rc=$?
  assert_eq "$rc" "0"
  [[ $out == *tokyo-night* && $out == *gruvbox* ]] || fail "list missing themes: $out"
}

test_theme_unknown_name_fails() {
  local err
  err=$("$ROOT/bin/ducal" theme nope 2>&1 >/dev/null); local rc=$?
  assert_eq "$rc" "1"
  [[ $err == *"Unknown theme: nope"* ]] || fail "stderr: $err"
}

test_theme_apply_switches_every_target() {
  mkdir -p "$HOME/.config/btop" "$HOME/.config/Code/User" "$HOME/.config/gtk-4.0"
  printf 'color_theme = "/usr/share/btop/themes/tokyo-night.theme"\n' > "$HOME/.config/btop/btop.conf"
  printf '{\n  "workbench.colorTheme": "Tokyo Night",\n  "editor.fontSize": 17\n}\n' > "$HOME/.config/Code/User/settings.json"
  printf '@import url("file:///old.css");\n/* user rules */\n' > "$HOME/.config/gtk-4.0/gtk.css"

  "$ROOT/bin/ducal" theme gruvbox >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  local t="$ROOT/themes/gruvbox"
  assert_link "$HOME/.config/kitty/current-theme.conf" "$t/kitty.conf"
  assert_link "$HOME/.config/fish/conf.d/ducal-theme.fish" "$t/fish.fish"
  assert_link "$HOME/.config/starship.toml" "$t/starship.toml"
  assert_link "$HOME/.config/lazygit/config.yml" "$t/lazygit.yml"
  assert_contains "$HOME/.config/btop/btop.conf" 'gruvbox_material_dark.theme'
  assert_contains "$HOME/.config/Code/User/settings.json" '"workbench.colorTheme": "Gruvbox Dark Medium"'
  assert_contains "$HOME/.config/Code/User/settings.json" '"editor.fontSize": 17'
  assert_contains "$HOME/.config/gtk-4.0/gtk.css" '/* user rules */'
  assert_eq "$(cat "$HOME/.config/ducal/current")" "gruvbox"
  assert_contains "$STUB_LOG" "dconf write /org/gnome/shell/extensions/search-light/border-color (0.490, 0.682, 0.639, 1.0)"
  assert_contains "$STUB_LOG" "dconf write /org/gnome/shell/extensions/user-theme/name 'Ducal'"
  assert_contains "$HOME/.themes/Ducal/gnome-shell/gnome-shell.css" '#282828'
  assert_not_contains "$HOME/.themes/Ducal/gnome-shell/gnome-shell.css" '{{'
}

test_theme_apply_without_gnome_only_themes_the_terminal() {
  rm -f "$SANDBOX/stubs/gsettings" "$SANDBOX/stubs/dconf"
  LC_ALL=C PATH="$SANDBOX/stubs:/usr/bin:/bin" DUCAL_NO_GNOME=1 "$ROOT/bin/ducal" theme gruvbox >/dev/null 2>"$SANDBOX/err"; local rc=$?
  assert_eq "$rc" "0"
  assert_link "$HOME/.config/starship.toml" "$ROOT/themes/gruvbox/starship.toml"
  assert_link "$HOME/.config/fish/conf.d/ducal-theme.fish" "$ROOT/themes/gruvbox/fish.fish"
  assert_not_contains "$SANDBOX/err" "not found"
  [[ ! -d $HOME/.local/share/ducal/wallpapers ]] || fail "wallpaper generated without GNOME"
  [[ ! -e $HOME/.themes/Ducal ]] || fail "shell theme written without GNOME"
}

test_theme_apply_twice_is_idempotent() {
  "$ROOT/bin/ducal" theme tokyo-night >/dev/null 2>&1
  "$ROOT/bin/ducal" theme tokyo-night >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_eq "$(find "$HOME" -name '*.ducal-backup-*' | wc -l)" "0" "no backups of our own links"
}

# ---------------------------------------------------------------- installer
test_install_list_shows_modules() {
  local out
  out=$("$ROOT/install.sh" --list); local rc=$?
  assert_eq "$rc" "0"
  [[ $out == *config* ]] || fail "modules: $out"
}

test_install_unknown_module_fails() {
  "$ROOT/install.sh" --only nope >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "1"
}

test_config_module_links_configs_and_cli_idempotently() {
  mkdir -p "$HOME/.config/kitty"; echo "old kitty" > "$HOME/.config/kitty/kitty.conf"
  "$ROOT/install.sh" --only config >/dev/null 2>&1; local rc1=$?
  "$ROOT/install.sh" --only config >/dev/null 2>&1; local rc2=$?
  assert_eq "$rc1/$rc2" "0/0"
  assert_link "$HOME/.config/kitty/kitty.conf" "$ROOT/config/kitty/kitty.conf"
  assert_link "$HOME/.config/nvim" "$ROOT/config/nvim"
  assert_link "$HOME/.local/bin/ducal" "$ROOT/bin/ducal"
  assert_eq "$(ls "$HOME/.config/kitty" | grep -c 'kitty.conf.ducal-backup-')" "1" "user file kept once"
  [[ -f $HOME/.config/btop/btop.conf && ! -L $HOME/.config/btop/btop.conf ]] || fail "btop.conf must be a copy"
}

test_config_module_never_overwrites_seeded_files() {
  mkdir -p "$HOME/.config/btop"; echo "my btop" > "$HOME/.config/btop/btop.conf"
  "$ROOT/install.sh" --only config >/dev/null 2>&1
  assert_eq "$(cat "$HOME/.config/btop/btop.conf")" "my btop"
}

test_config_module_sets_up_the_claude_status_line() {
  printf '#!/usr/bin/env bash\n' > "$SANDBOX/stubs/ccstatusline"; chmod +x "$SANDBOX/stubs/ccstatusline"
  mkdir -p "$HOME/.claude"; echo '{"model": "opus", "env": {"A": "1"}}' > "$HOME/.claude/settings.json"
  "$ROOT/install.sh" --only config >/dev/null 2>&1; local rc1=$?
  "$ROOT/install.sh" --only config >/dev/null 2>&1; local rc2=$?
  assert_eq "$rc1/$rc2" "0/0"
  assert_eq "$(jq -c '.statusLine' "$HOME/.claude/settings.json")" '{"type":"command","command":"ccstatusline","padding":0,"refreshInterval":10}'
  assert_eq "$(jq -c '[.model, .env.A]' "$HOME/.claude/settings.json")" '["opus","1"]' "existing settings kept"
  assert_eq "$(jq -r '.powerline.theme' "$HOME/.config/ccstatusline/settings.json")" "tokyonight"
}

test_config_module_keeps_an_existing_claude_status_line() {
  printf '#!/usr/bin/env bash\n' > "$SANDBOX/stubs/ccstatusline"; chmod +x "$SANDBOX/stubs/ccstatusline"
  mkdir -p "$HOME/.claude" "$HOME/.config/ccstatusline"
  echo '{"statusLine": {"type": "command", "command": "mine"}}' > "$HOME/.claude/settings.json"
  echo '{"mine": true}' > "$HOME/.config/ccstatusline/settings.json"
  # without a terminal (or with DUCAL_CLAUDE_STATUSLINE=keep) yours stays
  # setsid: no controlling terminal, as when nobody can answer
  setsid -w "$ROOT/install.sh" --only config >/dev/null 2>&1 </dev/null
  assert_eq "$(jq -r '.statusLine.command' "$HOME/.claude/settings.json")" "mine"
  assert_eq "$(cat "$HOME/.config/ccstatusline/settings.json")" '{"mine": true}'
}

test_config_module_replaces_the_status_line_when_asked() {
  printf '#!/usr/bin/env bash\n' > "$SANDBOX/stubs/ccstatusline"; chmod +x "$SANDBOX/stubs/ccstatusline"
  mkdir -p "$HOME/.claude" "$HOME/.config/ccstatusline"
  echo '{"model": "opus", "statusLine": {"type": "command", "command": "mine"}}' > "$HOME/.claude/settings.json"
  echo '{"mine": true}' > "$HOME/.config/ccstatusline/settings.json"
  DUCAL_CLAUDE_STATUSLINE=replace "$ROOT/install.sh" --only config >"$SANDBOX/out" 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_eq "$(jq -c '.statusLine' "$HOME/.claude/settings.json")" '{"type":"command","command":"ccstatusline","padding":0,"refreshInterval":10}'
  assert_eq "$(jq -r '.model' "$HOME/.claude/settings.json")" "opus" "other settings kept"
  assert_eq "$(jq -r '.powerline.theme' "$HOME/.config/ccstatusline/settings.json")" "tokyonight"
  # the previous style is backed up, not lost
  assert_eq "$(cat "$HOME"/.config/ccstatusline/settings.json.ducal-backup-*)" '{"mine": true}'
  assert_contains "$SANDBOX/out" "Claude Code status line ready"
}

test_config_module_does_not_ask_when_the_status_line_is_already_ducal() {
  printf '#!/usr/bin/env bash\n' > "$SANDBOX/stubs/ccstatusline"; chmod +x "$SANDBOX/stubs/ccstatusline"
  "$ROOT/install.sh" --only config >/dev/null 2>&1
  # ccstatusline adds its own install info: still the ducal style
  jq '. + {installation: {installedVersion: "2.2.34", method: "pinned"}}' "$HOME/.config/ccstatusline/settings.json" > "$SANDBOX/s" &&
    cp "$SANDBOX/s" "$HOME/.config/ccstatusline/settings.json"
  DUCAL_CLAUDE_STATUSLINE=replace "$ROOT/install.sh" --only config >"$SANDBOX/out" 2>&1
  assert_not_contains "$SANDBOX/out" "Replace it with the ducal one"
  [[ -z $(ls "$HOME"/.config/ccstatusline/*ducal-backup* 2>/dev/null) ]] || fail "no backup expected"
  assert_eq "$(jq -r '.installation.method' "$HOME/.config/ccstatusline/settings.json")" "pinned"
}

test_config_module_skips_the_status_line_without_ccstatusline() {
  PATH="$SANDBOX/stubs:/usr/bin:/bin" "$ROOT/install.sh" --only config >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  [[ ! -e $HOME/.claude/settings.json ]] || fail "settings.json must not be created without ccstatusline"
}

# ---------------------------------------------------------------- preflight
# A healthy Ubuntu 24.04 x86_64 with sudo, internet and every prerequisite.
# Tweak: $SANDBOX/arch, $SANDBOX/uid, $SANDBOX/sudo-fails, $SANDBOX/offline, $SANDBOX/installed
stub_preflight() {
  stub_package_tools
  local s="$SANDBOX/stubs"
  printf '%s\n' curl git python3 ca-certificates whiptail > "$SANDBOX/installed"
  echo x86_64 > "$SANDBOX/arch"; echo 1000 > "$SANDBOX/uid"
  printf '#!/usr/bin/env bash\n[[ $1 == -m ]] && cat "%s/arch" || /usr/bin/uname "$@"\n' "$SANDBOX" > "$s/uname"
  printf '#!/usr/bin/env bash\n[[ $1 == -u ]] && cat "%s/uid" || /usr/bin/id "$@"\n' "$SANDBOX" > "$s/id"
  printf '#!/usr/bin/env bash\nif [[ $1 == -v ]]; then echo "sudo -v" >> "$STUB_LOG"; [[ ! -f "%s/sudo-fails" ]]; exit; fi\n"$@"\n' "$SANDBOX" > "$s/sudo"
  # with -I, prints the HTTP headers in $SANDBOX/headers (the server Date)
  printf '#!/usr/bin/env bash\necho "curl $*" >> "$STUB_LOG"\n[[ ! -f "%s/offline" ]] || exit 1\n[[ $1 == -*I* && -f "%s/headers" ]] && cat "%s/headers"\nexit 0\n' "$SANDBOX" "$SANDBOX" "$SANDBOX" > "$s/curl"
  chmod +x "$s"/*
  export DUCAL_SYSROOT="$SANDBOX/root"
  mkdir -p "$DUCAL_SYSROOT/etc"
  printf 'NAME="Ubuntu"\nVERSION_ID="24.04"\nID=ubuntu\n' > "$DUCAL_SYSROOT/etc/os-release"
}

# preflight CODE — runs CODE with lib/preflight.sh loaded
preflight() { bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/groups.sh'; source '$ROOT/lib/preflight.sh'; $1" </dev/null; }

test_preflight_passes_on_a_ready_system() {
  stub_preflight
  preflight preflight_system >"$SANDBOX/out" 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$SANDBOX/out" "Ubuntu 24.04"
  assert_contains "$STUB_LOG" "sudo -v"
  assert_contains "$STUB_LOG" "curl -fsS --max-time 10 -o /dev/null https://github.com"
  assert_not_contains "$STUB_LOG" "apt-get"
}

# apt rejects package lists "not valid yet" when the clock is behind
test_preflight_stops_when_the_clock_is_off() {
  stub_preflight
  printf 'HTTP/2 200\r\ndate: %s\r\n' "$(LC_ALL=C date -u -d '+3 hours 30 seconds' '+%a, %d %b %Y %H:%M:%S GMT')" > "$SANDBOX/headers"
  preflight preflight_system >"$SANDBOX/out" 2>&1; local rc=$?
  assert_eq "$rc" "1"
  assert_contains "$SANDBOX/out" "Your clock is off by 180 minutes"
  assert_contains "$SANDBOX/out" "sudo timedatectl set-ntp true"
}

test_preflight_accepts_a_clock_in_time() {
  stub_preflight
  printf 'HTTP/2 200\r\ndate: %s\r\n' "$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S GMT')" > "$SANDBOX/headers"
  preflight preflight_system >"$SANDBOX/out" 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$SANDBOX/out" "Clock in time"
}

test_preflight_installs_missing_prerequisites() {
  stub_preflight
  printf '%s\n' curl python3 ca-certificates > "$SANDBOX/installed"
  preflight preflight_system >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$STUB_LOG" "apt-get update"
  assert_contains "$STUB_LOG" "apt-get install -y git whiptail"
}

test_preflight_stops_when_a_prerequisite_is_not_available() {
  stub_preflight
  printf '%s\n' curl python3 ca-certificates git > "$SANDBOX/installed"
  echo whiptail > "$SANDBOX/no-candidate"
  preflight preflight_system >/dev/null 2>"$SANDBOX/err"; local rc=$?
  assert_eq "$rc" "1"
  assert_contains "$SANDBOX/err" "whiptail is not available from apt"
  assert_not_contains "$STUB_LOG" "apt-get install"
}

test_preflight_stops_on_an_unsupported_system() {
  stub_preflight
  local err
  echo aarch64 > "$SANDBOX/arch"
  err=$(preflight preflight_system 2>&1); assert_eq "$?" "1" "arch"
  [[ $err == *"x86_64"*"aarch64"* ]] || fail "arch message: $err"
  echo x86_64 > "$SANDBOX/arch"; echo 0 > "$SANDBOX/uid"
  err=$(preflight preflight_system 2>&1); assert_eq "$?" "1" "root"
  [[ $err == *"not as root"* ]] || fail "root message: $err"
  echo 1000 > "$SANDBOX/uid"; touch "$SANDBOX/sudo-fails"
  err=$(preflight preflight_system 2>&1); assert_eq "$?" "1" "sudo"
  [[ $err == *"sudo"* ]] || fail "sudo message: $err"
  rm "$SANDBOX/sudo-fails"; touch "$SANDBOX/offline"
  err=$(preflight preflight_system 2>&1); assert_eq "$?" "1" "offline"
  [[ $err == *"internet"* ]] || fail "offline message: $err"
  # nothing was installed on the way out
  assert_not_contains "$STUB_LOG" "apt-get install"
}

test_preflight_needs_apt() {
  stub_preflight
  rm "$SANDBOX/stubs/apt-get"
  local err; err=$(PATH="$SANDBOX/stubs:/bin/nonexistent" /bin/bash -c "PATH='$SANDBOX/stubs'; source '$ROOT/lib/common.sh'; source '$ROOT/lib/groups.sh'; source '$ROOT/lib/preflight.sh'; preflight_system" 2>&1); local rc=$?
  assert_eq "$rc" "1"
  [[ $err == *"apt"* ]] || fail "apt message: $err"
}

test_preflight_warns_on_an_untested_version() {
  stub_preflight
  printf 'NAME="Ubuntu"\nVERSION_ID="22.04"\nID=ubuntu\n' > "$DUCAL_SYSROOT/etc/os-release"
  preflight preflight_system >/dev/null 2>"$SANDBOX/err"; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$SANDBOX/err" "22.04 is untested"
  assert_contains "$SANDBOX/err" "ducal supports 24.04 or newer"
}

test_preflight_accepts_newer_ubuntu_releases() {
  stub_preflight
  local v
  for v in 24.10 25.04 25.10 26.04 30.10; do
    printf 'NAME="Ubuntu"\nVERSION_ID="%s"\nID=ubuntu\n' "$v" > "$DUCAL_SYSROOT/etc/os-release"
    preflight preflight_system >"$SANDBOX/out" 2>"$SANDBOX/err"; local rc=$?
    assert_eq "$rc" "0" "$v"
    assert_not_contains "$SANDBOX/err" "untested"
    assert_contains "$SANDBOX/out" "System: Ubuntu $v x86_64"
  done
}

test_preflight_needs_gnome_for_the_desktop_groups() {
  stub_preflight
  local err
  err=$(PATH="$SANDBOX/stubs:/usr/bin:/bin" DUCAL_NO_GNOME=1 DUCAL_GROUPS_SELECTED="terminal gnome" preflight preflight_groups 2>&1); assert_eq "$?" "1"
  [[ $err == *"GNOME"*"--profile dev"* ]] || fail "gnome message: $err"
  DUCAL_NO_GNOME=1 DUCAL_GROUPS_SELECTED="terminal languages" preflight preflight_groups >/dev/null 2>&1; assert_eq "$?" "0" "dev groups need no GNOME"
}

test_preflight_install_with_gnome_groups_changes_nothing() {
  stub_preflight
  DUCAL_NO_GNOME=1 "$ROOT/install.sh" --profile desktop >/dev/null 2>"$SANDBOX/err"; assert_eq "$?" "1"
  assert_contains "$SANDBOX/err" "--profile dev"
  assert_not_contains "$STUB_LOG" "apt-get"
  [[ -z $(ls -A "$HOME") ]] || fail "HOME changed: $(ls -A "$HOME")"
}

test_preflight_wsl_desktop_profile_drops_gnome() {
  stub_preflight
  DUCAL_WSL=1 DUCAL_NO_GNOME=1 DUCAL_PROFILE=desktop preflight 'select_install; preflight_groups' >/dev/null 2>&1
  assert_eq "$?" "0"
}

test_preflight_offline_with_a_missing_prerequisite_installs_nothing() {
  stub_preflight
  sed -i '/^whiptail$/d' "$SANDBOX/installed"; touch "$SANDBOX/offline"
  preflight preflight_system >/dev/null 2>&1; assert_eq "$?" "1"
  assert_not_contains "$STUB_LOG" "apt-get"
}

test_preflight_low_disk_only_warns() {
  stub_preflight
  printf '#!/usr/bin/env bash\necho h\necho "/dev/x 1 1 1000 99%% /"\n' > "$SANDBOX/stubs/df"; chmod +x "$SANDBOX/stubs/df"
  preflight preflight_system >/dev/null 2>"$SANDBOX/err"; assert_eq "$?" "0"
  assert_contains "$SANDBOX/err" "Less than 5 GB free"
}

test_preflight_disk_check_failure_does_not_stop_the_install() {
  stub_preflight
  printf '#!/usr/bin/env bash\nexit 1\n' > "$SANDBOX/stubs/df"; chmod +x "$SANDBOX/stubs/df"
  preflight 'set -euo pipefail; preflight_system' >/dev/null 2>&1; assert_eq "$?" "0"
}

test_install_runs_the_preflight_before_anything() {
  stub_preflight
  echo aarch64 > "$SANDBOX/arch"
  DUCAL_GROUPS=terminal "$ROOT/install.sh" >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "1"
  assert_not_contains "$STUB_LOG" "apt-get"
  # --only keeps running a module without the checks
  DUCAL_GROUPS_SELECTED="languages" "$ROOT/install.sh" --only config >/dev/null 2>&1
  assert_eq "$?" "0" "--only skips the preflight"
}

# ---------------------------------------------------------------- boot
# fake_ducal_repo DIR — a git repo whose install.sh logs its arguments
fake_ducal_repo() {
  mkdir -p "$1"
  printf '#!/usr/bin/env bash\necho "install $*" >> "$STUB_LOG"\n' > "$1/install.sh"
  chmod +x "$1/install.sh"
  git -C "$1" init -q && git -C "$1" add . && git -C "$1" -c user.name=t -c user.email=t@t commit -qm init
}

test_boot_clones_ducal_and_runs_the_installer() {
  fake_ducal_repo "$SANDBOX/repo"
  DUCAL_REPO="$SANDBOX/repo" bash -s -- --profile dev < "$ROOT/boot.sh" >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  [[ -x $HOME/.local/share/ducal/install.sh ]] || fail "ducal not cloned into ~/.local/share/ducal"
  assert_contains "$STUB_LOG" "install --profile dev"
}

test_boot_updates_an_existing_copy() {
  fake_ducal_repo "$SANDBOX/repo"
  DUCAL_REPO="$SANDBOX/repo" bash < "$ROOT/boot.sh" >/dev/null 2>&1
  echo new > "$SANDBOX/repo/NEW" && git -C "$SANDBOX/repo" add NEW && git -C "$SANDBOX/repo" -c user.name=t -c user.email=t@t commit -qm new
  DUCAL_REPO="$SANDBOX/repo" bash < "$ROOT/boot.sh" >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  [[ -f $HOME/.local/share/ducal/NEW ]] || fail "existing copy not updated"
  assert_eq "$(grep -c '^install' "$STUB_LOG")" "2"
}

test_boot_reports_the_installer_failure() {
  fake_ducal_repo "$SANDBOX/repo"
  printf '#!/usr/bin/env bash\nexit 3\n' > "$SANDBOX/repo/install.sh"
  git -C "$SANDBOX/repo" -c user.name=t -c user.email=t@t commit -qam fail
  DUCAL_REPO="$SANDBOX/repo" bash < "$ROOT/boot.sh" >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "3"
}

# ---------------------------------------------------------------- groups
# groups CODE — runs CODE with lib/groups.sh loaded, outside a terminal
groups() { bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/groups.sh'; $1" </dev/null; }

test_groups_parse_validates_and_orders() {
  assert_eq "$(DUCAL_WSL=0 groups 'parse_groups "gnome, terminal"')" "terminal gnome"
  assert_eq "$(DUCAL_WSL=0 groups 'parse_groups all')" "terminal languages desktop-apps gnome system cleanup"
  assert_eq "$(DUCAL_WSL=0 groups 'parse_groups none')" ""
  local err; err=$(DUCAL_WSL=0 groups 'parse_groups terminal,games' 2>&1); local rc=$?
  assert_eq "$rc" "1"
  [[ $err == *"Unknown group: games"* ]] || fail "unknown group message: $err"
}

test_groups_on_wsl_only_offer_the_terminal_ones() {
  assert_eq "$(DUCAL_WSL=1 groups 'available_groups')" "terminal languages"
  local err; err=$(DUCAL_WSL=1 groups 'parse_groups terminal,gnome,languages' 2>"$SANDBOX/err")
  assert_eq "$err" "terminal languages"
  assert_contains "$SANDBOX/err" "gnome is not available on WSL"
}

test_groups_profiles() {
  assert_eq "$(DUCAL_WSL=0 groups 'profile_groups desktop')" "terminal desktop-apps gnome"
  assert_eq "$(DUCAL_WSL=0 groups 'profile_groups dev')" "terminal languages"
  DUCAL_WSL=0 groups 'profile_groups gaming' >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "1"
}

test_groups_resolve_without_a_terminal() {
  assert_eq "$(DUCAL_WSL=0 groups 'resolve_groups')" "terminal desktop-apps gnome" "desktop default"
  assert_eq "$(DUCAL_WSL=1 groups 'resolve_groups')" "terminal languages" "WSL default"
  assert_eq "$(DUCAL_WSL=0 DUCAL_PROFILE=dev groups 'resolve_groups')" "terminal languages"
  assert_eq "$(DUCAL_WSL=0 DUCAL_PROFILE=dev DUCAL_GROUPS=terminal,system groups 'resolve_groups')" "terminal system" "DUCAL_GROUPS wins"
}

# whiptail stub: logs its arguments, answers with $SANDBOX/picked on stderr (cancels without it)
stub_whiptail() {
  printf '#!/usr/bin/env bash\necho "whiptail $*" >> "$STUB_LOG"\n[[ -f "%s/picked" ]] || exit 1\ncat "%s/picked" >&2\n' "$SANDBOX" "$SANDBOX" > "$SANDBOX/stubs/whiptail"
  chmod +x "$SANDBOX/stubs/whiptail"
}

test_groups_menu_uses_a_checklist() {
  stub_whiptail
  printf 'terminal\nlanguages\n' > "$SANDBOX/picked"
  assert_eq "$(DUCAL_WSL=0 groups 'menu_groups')" "terminal languages"
  assert_contains "$STUB_LOG" "--checklist"
  assert_contains "$STUB_LOG" "desktop-apps"
  # WSL: only the terminal groups are offered
  : > "$STUB_LOG"
  DUCAL_WSL=1 groups 'menu_groups' >/dev/null
  assert_not_contains "$STUB_LOG" "gnome"
  assert_contains "$STUB_LOG" "languages"
}

test_groups_menus_offer_everything_first() {
  stub_whiptail
  printf 'all\n' > "$SANDBOX/picked"
  assert_eq "$(DUCAL_WSL=0 groups 'menu_groups')" "terminal languages desktop-apps gnome system cleanup"
  assert_eq "$(DUCAL_WSL=1 groups 'menu_groups')" "terminal languages" "WSL: everything it offers"
  assert_eq "$(groups 'menu_items languages')" "node go rust docker"
  # "all" is the first entry of the checklist
  grep -qE -- '--checklist .* [0-9]+ all Everything below ' "$STUB_LOG" || fail "all is not the first entry: $(head -1 "$STUB_LOG")"
  # ticking all plus some others is still all
  printf 'all\ngo\n' > "$SANDBOX/picked"
  assert_eq "$(groups 'menu_items languages')" "node go rust docker"
}

test_groups_question_fallback_offers_everything_first() {
  local answers
  answers=$(printf 'y\n' | PATH="$SANDBOX/stubs:/usr/bin:/bin" DUCAL_WSL=0 DUCAL_NO_WHIPTAIL=1 \
    bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/groups.sh'; menu_groups" 2>/dev/null)
  assert_eq "$answers" "terminal languages desktop-apps gnome system cleanup"
}

test_groups_menu_cancel_aborts() {
  stub_whiptail
  DUCAL_WSL=0 groups 'menu_groups' >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "1"
}

test_groups_items_menu_picks_extras() {
  stub_whiptail
  printf 'node\nrust\n' > "$SANDBOX/picked"
  assert_eq "$(groups 'menu_items languages')" "node rust"
  assert_contains "$STUB_LOG" "docker"
}

test_groups_menu_falls_back_to_questions_without_whiptail() {
  local answers
  answers=$(printf 'n\ny\nn\nn\nn\nn\nn\n' | PATH="$SANDBOX/stubs:/usr/bin:/bin" DUCAL_WSL=0 DUCAL_NO_WHIPTAIL=1 \
    bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/groups.sh'; menu_groups" 2>/dev/null)
  assert_eq "$answers" "terminal"
}

# ---------------------------------------------------------------- apps
# Stubs for package tools: sudo runs the command, apt-get/curl only log.
stub_package_tools() {
  local s="$SANDBOX/stubs"
  printf '#!/usr/bin/env bash\n"$@"\n' > "$s/sudo"
  printf '#!/usr/bin/env bash\necho "apt-get $*" >> "$STUB_LOG"\n' > "$s/apt-get"
  printf '#!/usr/bin/env bash\necho "curl $*" >> "$STUB_LOG"\nexit 1\n' > "$s/curl"
  # dpkg-query reports only the packages listed in $SANDBOX/installed as installed
  printf '#!/usr/bin/env bash\npkg="${@: -1}"\ngrep -qx "$pkg" "%s/installed" && echo "install ok installed" || exit 1\n' "$SANDBOX" > "$s/dpkg-query"
  # apt-cache: no candidate for packages in $SANDBOX/no-candidate, nor for those
  # in $SANDBOX/stale-lists until `apt-get update` ran
  cat > "$s/apt-cache" <<EOF
#!/usr/bin/env bash
pkg="\${@: -1}"
if grep -qx "\$pkg" "$SANDBOX/no-candidate" 2>/dev/null ||
  { grep -qx "\$pkg" "$SANDBOX/stale-lists" 2>/dev/null && ! grep -q "apt-get update" "\$STUB_LOG"; }; then
  version="(none)"
else
  version=1.0
fi
# Like the real one: localized unless LC_ALL=C, and a long version table after
# the candidate (a reader that stops early makes it fail with SIGPIPE)
label=Candidate; [[ \${LC_ALL:-} == C ]] || label=Candidato
printf '%s:\\n  Installed: (none)\\n  %s: %s\\n  Version table:\\n' "\$pkg" "\$label" "\$version"
seq 1 50000
EOF
  chmod +x "$s"/*
  : > "$SANDBOX/installed"
}

# Fake an installed command so its installer is skipped.
fake_cmd() { printf '#!/usr/bin/env bash\n' > "$SANDBOX/stubs/$1"; chmod +x "$SANDBOX/stubs/$1"; }

test_apt_install_only_installs_missing_packages() {
  stub_package_tools
  echo "git" > "$SANDBOX/installed"
  bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; apt_install git btop" >/dev/null 2>&1
  assert_contains "$STUB_LOG" "apt-get install -y btop"
  assert_not_contains "$STUB_LOG" "install -y git"
}

# A newer Ubuntu may drop a package: skip it with a warning, install the rest
test_apt_install_skips_a_package_this_release_does_not_have() {
  stub_package_tools
  echo "gtk2-engines-murrine" > "$SANDBOX/no-candidate"
  # pipefail, as in install.sh
  bash -o pipefail -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; apt_install btop gtk2-engines-murrine" >/dev/null 2>"$SANDBOX/err"; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$STUB_LOG" "apt-get install -y btop"
  assert_not_contains "$STUB_LOG" "gtk2-engines-murrine"
  assert_contains "$SANDBOX/err" "gtk2-engines-murrine is not available on this release, skipping it"
  assert_eq "$(grep -c 'apt-get update' "$STUB_LOG")" "1" "lists refreshed once before giving up"
}

# Old package lists are not a missing package: refresh them, then install
test_apt_install_refreshes_stale_lists_before_skipping() {
  stub_package_tools
  printf 'btop\nfish\n' > "$SANDBOX/stale-lists"
  bash -o pipefail -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; apt_install btop fish" >/dev/null 2>"$SANDBOX/err"; local rc=$?
  assert_eq "$rc" "0"
  assert_eq "$(grep -c 'apt-get update' "$STUB_LOG")" "1"
  assert_contains "$STUB_LOG" "apt-get install -y btop fish"
  assert_not_contains "$SANDBOX/err" "skipping"
}

# Docker publishes a new Ubuntu release months later: use the 24.04 repository meanwhile
test_docker_repo_falls_back_to_noble_for_an_unpublished_release() {
  mkdir -p "$SANDBOX/root/etc"
  printf 'ID=ubuntu\nVERSION_CODENAME=zesty2\n' > "$SANDBOX/root/etc/os-release"
  cat > "$SANDBOX/stubs/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >> "$STUB_LOG"
[[ ${@: -1} == */dists/questing/Release ]] # only questing is published
EOF
  chmod +x "$SANDBOX/stubs/curl"
  local out
  out=$(DUCAL_SYSROOT="$SANDBOX/root" bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; docker_repo_codename" 2>"$SANDBOX/err")
  assert_eq "$out" "noble"
  assert_contains "$SANDBOX/err" "Docker has no packages for Ubuntu zesty2 yet, using the 24.04 (noble) ones"
  printf 'ID=ubuntu\nVERSION_CODENAME=questing\n' > "$SANDBOX/root/etc/os-release"
  out=$(DUCAL_SYSROOT="$SANDBOX/root" bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; docker_repo_codename" 2>/dev/null)
  assert_eq "$out" "questing"
  assert_contains "$STUB_LOG" "https://download.docker.com/linux/ubuntu/dists/questing/Release"
}

test_apt_install_does_nothing_when_all_installed() {
  stub_package_tools
  printf 'git\nbtop\n' > "$SANDBOX/installed"
  bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; apt_install git btop" >/dev/null 2>&1
  assert_not_contains "$STUB_LOG" "apt-get"
}

test_parse_extras_accepts_known_list_all_and_none() {
  local out
  out=$(bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; parse_extras 'chrome, code'")
  assert_eq "$out" "chrome code"
  out=$(bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; parse_extras all")
  assert_eq "$out" "chrome code docker go rust node steam discord"
  out=$(bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; parse_extras none")
  assert_eq "$out" ""
}

test_parse_extras_rejects_unknown_names() {
  local err
  err=$(bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; parse_extras 'chrome,nope'" 2>&1); local rc=$?
  assert_eq "$rc" "1"
  [[ $err == *"Unknown extra: nope"* ]] || fail "stderr: $err"
}

stub_lazygit_install() {
  stub_package_tools
  printf '%s\n' git curl unzip build-essential fish btop ripgrep fd-find gh > "$SANDBOX/installed"
  for c in nvim starship yazi ya fd claude opencode engram gentle-ai codegraph; do fake_cmd "$c"; done
  stub_installed_node
  printf '#!/usr/bin/env bash\necho "lazygit fixture"\n' > "$SANDBOX/lazygit"
  chmod +x "$SANDBOX/lazygit"
  tar -czf "$SANDBOX/lazygit.tar.gz" -C "$SANDBOX" lazygit
  export LAZYGIT_FIXTURE="$SANDBOX/lazygit.tar.gz"
  cat > "$SANDBOX/stubs/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >> "$STUB_LOG"
case "${@: -1}" in
  https://github.com/jesseduffield/lazygit/releases/latest)
    if [[ ${LAZYGIT_RELEASE_BLOCKED:-0} == 1 ]]; then
      echo "curl: (22) The requested URL returned error: 403" >&2
      exit 22
    fi
    printf '%s' https://github.com/jesseduffield/lazygit/releases/tag/v0.66.3 ;;
  https://github.com/jesseduffield/lazygit/releases/download/v0.66.3/lazygit_0.66.3_linux_x86_64.tar.gz)
    cp "$LAZYGIT_FIXTURE" "${@: -2:1}" ;;
  *) echo "curl: (22) The requested URL returned error: 403" >&2; exit 22 ;;
esac
EOF
}

test_apps_installs_lazygit_without_github_api_and_skips_it_on_rerun() {
  stub_lazygit_install
  PATH="$SANDBOX/stubs:/usr/bin:/bin" DUCAL_GROUPS_SELECTED=terminal DUCAL_EXTRAS=none \
    "$ROOT/install.sh" --only apps >"$SANDBOX/out" 2>"$SANDBOX/err"
  assert_eq "$?" "0"
  assert_contains "$SANDBOX/out" "Terminal tools ready"
  assert_eq "$("$HOME/.local/bin/lazygit")" "lazygit fixture"
  assert_contains "$STUB_LOG" "lazygit_0.66.3_linux_x86_64.tar.gz"
  assert_not_contains "$STUB_LOG" "api.github.com"

  : > "$STUB_LOG"
  PATH="$SANDBOX/stubs:/usr/bin:/bin" DUCAL_GROUPS_SELECTED=terminal DUCAL_EXTRAS=none \
    "$ROOT/install.sh" --only apps >"$SANDBOX/out" 2>"$SANDBOX/err"
  assert_eq "$?" "0"
  assert_eq "$("$HOME/.local/bin/lazygit")" "lazygit fixture"
  assert_not_contains "$STUB_LOG" "curl"
}

test_apps_reports_lazygit_release_failure_without_downloading_an_empty_url() {
  stub_lazygit_install
  PATH="$SANDBOX/stubs:/usr/bin:/bin" DUCAL_GROUPS_SELECTED=terminal DUCAL_EXTRAS=none LAZYGIT_RELEASE_BLOCKED=1 \
    "$ROOT/install.sh" --only apps >"$SANDBOX/out" 2>"$SANDBOX/err"
  assert_eq "$?" "1"
  assert_contains "$SANDBOX/err" "403"
  assert_contains "$SANDBOX/err" "Could not resolve the latest Lazygit release"
  assert_eq "$(grep -c '^curl ' "$STUB_LOG")" "1"
  [[ ! -e $HOME/.local/bin/lazygit ]] || fail "Lazygit was installed despite release lookup failure"
}

test_apps_rejects_invalid_lazygit_release_redirects() {
  stub_lazygit_install
  local releases=https://github.com/jesseduffield/lazygit/releases target
  local -x LAZYGIT_REDIRECT
  cat > "$SANDBOX/stubs/curl" <<'EOF'
#!/usr/bin/env bash
printf '<%s>\n' "${@: -1}" >> "$STUB_LOG"
printf '%s' "$LAZYGIT_REDIRECT"
EOF
  for target in '' "$releases/latest" \
    'https://example.invalid/jesseduffield/lazygit/releases/tag/v12.34.56' \
    "$releases/tag/v12.34.56-rc.1"; do
    LAZYGIT_REDIRECT=$target
    : > "$STUB_LOG"
    PATH="$SANDBOX/stubs:/usr/bin:/bin" DUCAL_GROUPS_SELECTED=terminal DUCAL_EXTRAS=none \
      "$ROOT/install.sh" --only apps >"$SANDBOX/out" 2>"$SANDBOX/err"
    assert_eq "$?" "1"
    assert_contains "$SANDBOX/err" "Unexpected Lazygit release URL: $target"
    assert_eq "$(cat "$STUB_LOG")" "<$releases/latest>"
    [[ ! -e $HOME/.local/bin/lazygit ]] || fail "Lazygit was installed despite an invalid redirect"
  done
}

# The .deb needs a newer glibc than Ubuntu 22.04 has: the static musl build runs anywhere
test_yazi_installs_the_static_build_not_the_deb() {
  stub_package_tools
  PATH="$SANDBOX/stubs:/usr/bin:/bin" bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; install_yazi" >/dev/null 2>&1
  assert_contains "$STUB_LOG" "yazi-x86_64-unknown-linux-musl.zip"
  assert_not_contains "$STUB_LOG" "yazi.deb"
  assert_not_contains "$STUB_LOG" "api.github.com/repos/sxyazi"
}

test_apps_module_skips_tools_already_installed() {
  stub_package_tools
  printf '%s\n' git curl unzip fontconfig build-essential fish btop ripgrep fd-find gh > "$SANDBOX/installed"
  for c in kitty nvim starship lazygit yazi ya fd claude opencode engram gentle-ai codegraph; do fake_cmd "$c"; done
  stub_installed_node
  mkdir -p "$HOME/.local/share/fonts/JetBrainsMonoNerd"
  DUCAL_EXTRAS=none "$ROOT/install.sh" --only apps >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_not_contains "$STUB_LOG" "curl"
  assert_not_contains "$STUB_LOG" "apt-get install"
}

# On a fresh system ~/.local/bin is not on PATH until the next login: what the
# installer puts there must still be found (ya right after yazi, reruns skip tools)
test_installer_finds_tools_in_local_bin() {
  stub_package_tools
  printf '%s\n' git curl unzip build-essential fish btop ripgrep fd-find gh > "$SANDBOX/installed"
  mkdir -p "$HOME/.local/bin"
  stub_installed_node
  for c in nvim starship lazygit yazi ya fd claude opencode engram gentle-ai codegraph; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "$STUB_LOG"\n' "$c" > "$HOME/.local/bin/$c"
    chmod +x "$HOME/.local/bin/$c"
  done
  PATH="$SANDBOX/stubs:/usr/bin:/bin" DUCAL_GROUPS_SELECTED="terminal" DUCAL_EXTRAS=none \
    "$ROOT/install.sh" --only apps >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_not_contains "$STUB_LOG" "curl"
  assert_contains "$STUB_LOG" "ya pkg add BennyOe/tokyo-night"
}

test_apps_module_installs_only_the_chosen_groups() {
  stub_package_tools
  printf '%s\n' git curl unzip build-essential fish btop ripgrep fd-find gh > "$SANDBOX/installed"
  for c in nvim starship lazygit yazi ya fd claude opencode engram gentle-ai codegraph; do fake_cmd "$c"; done
  stub_installed_node
  # terminal only: no kitty, no Nerd Font (and their packages)
  DUCAL_GROUPS_SELECTED="terminal" DUCAL_EXTRAS=none "$ROOT/install.sh" --only apps >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_not_contains "$STUB_LOG" "kovidgoyal"
  assert_not_contains "$STUB_LOG" "nerd-fonts"
  assert_not_contains "$STUB_LOG" "fontconfig"
  # desktop apps only: kitty and the font, no terminal tools
  : > "$STUB_LOG"
  # keep any real kitty on the host PATH out of the sandbox
  PATH="$SANDBOX/stubs:/usr/bin:/bin" DUCAL_GROUPS_SELECTED="desktop-apps" DUCAL_EXTRAS=none "$ROOT/install.sh" --only apps >/dev/null 2>&1
  assert_contains "$STUB_LOG" "kovidgoyal"
  assert_not_contains "$STUB_LOG" "fish"
}

test_opencode_uses_the_official_installer_without_touching_shell_files() {
  stub_package_tools
  printf '#!/usr/bin/env bash\necho "curl $*" >> "%s"\necho "echo \\"opencode-installer \\$*\\" >> %s; mkdir -p \\$HOME/.opencode/bin; touch \\$HOME/.opencode/bin/opencode"\n' "$STUB_LOG" "$STUB_LOG" > "$SANDBOX/stubs/curl"
  chmod +x "$SANDBOX/stubs/curl"
  PATH="$SANDBOX/stubs:/usr/bin:/bin" bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; install_opencode" >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$STUB_LOG" "curl -fsSL https://opencode.ai/install"
  assert_contains "$STUB_LOG" "opencode-installer --no-modify-path"
  assert_link "$HOME/.local/bin/opencode" "$HOME/.opencode/bin/opencode"
}

test_opencode_is_skipped_when_already_installed() {
  stub_package_tools
  fake_cmd opencode
  bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; install_opencode" >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_not_contains "$STUB_LOG" "curl"
}

test_desktop_modules_skip_when_their_group_is_not_chosen() {
  local m rc
  for m in gnome assets system cleanup; do
    : > "$STUB_LOG"
    PATH="$SANDBOX/stubs:/usr/bin:/bin" DUCAL_GROUPS_SELECTED="terminal languages" DUCAL_SYSTEM=yes DUCAL_CLEANUP=all \
      "$ROOT/install.sh" --only "$m" >/dev/null 2>&1; rc=$?
    assert_eq "$rc" "0" "$m"
    [[ ! -s $STUB_LOG ]] || fail "$m ran: $(head -3 "$STUB_LOG")"
  done
}

test_config_module_for_the_terminal_only() {
  DUCAL_GROUPS_SELECTED="terminal languages" "$ROOT/install.sh" --only config >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_link "$HOME/.config/fish/config.fish" "$ROOT/config/fish/config.fish"
  assert_link "$HOME/.config/nvim" "$ROOT/config/nvim"
  [[ ! -e $HOME/.config/kitty/kitty.conf ]] || fail "kitty.conf linked without desktop-apps"
  [[ ! -e $HOME/.config/gtk-4.0/gtk.css ]] || fail "gtk.css seeded without gnome"
  # without the GNOME group nothing else applies the default theme: config does
  assert_link "$HOME/.config/starship.toml" "$ROOT/themes/tokyo-night/starship.toml"
  assert_eq "$(cat "$HOME/.config/ducal/current")" "tokyo-night"
}

test_selection_sets_the_answers_for_every_module() {
  local out
  out=$(DUCAL_WSL=0 DUCAL_GROUPS=terminal,languages,system groups 'select_install && echo "$DUCAL_GROUPS_SELECTED|$DUCAL_EXTRAS|$DUCAL_SYSTEM|$DUCAL_CLEANUP"')
  assert_eq "$out" "terminal languages system|none|yes|none"
  out=$(DUCAL_WSL=0 DUCAL_GROUPS=terminal,cleanup DUCAL_EXTRAS=go groups 'select_install && echo "$DUCAL_GROUPS_SELECTED|$DUCAL_EXTRAS|$DUCAL_SYSTEM|${DUCAL_CLEANUP:-ask}"')
  assert_eq "$out" "terminal cleanup|go|no|ask" "explicit answers win; cleanup still asks which"
}

test_selection_asks_for_the_items_of_the_chosen_groups() {
  stub_whiptail
  printf 'node\n' > "$SANDBOX/picked"
  # stdin is not a terminal here, so force the item menu
  out=$(DUCAL_WSL=0 DUCAL_GROUPS=terminal,languages DUCAL_ASK_ITEMS=1 groups 'select_install && echo "$DUCAL_EXTRAS"')
  assert_eq "$out" "node"
  assert_contains "$STUB_LOG" "docker"
  assert_not_contains "$STUB_LOG" "chrome"
}

test_explicit_system_and_cleanup_answers_still_apply() {
  local out
  out=$(DUCAL_SYSTEM=yes DUCAL_CLEANUP=apps DUCAL_WSL=0 groups 'select_install; echo "$DUCAL_SYSTEM|$DUCAL_CLEANUP|$(group_on system && echo on)|$(group_on cleanup && echo on)"' 2>/dev/null)
  assert_eq "$out" "yes|apps|on|on"
}

test_default_run_without_answers_skips_system_and_cleanup() {
  local out
  out=$(DUCAL_WSL=0 groups 'select_install; echo "$DUCAL_GROUPS_SELECTED|$DUCAL_SYSTEM|$DUCAL_CLEANUP|$DUCAL_EXTRAS"' 2>/dev/null)
  assert_eq "$out" "terminal desktop-apps gnome|no|none|none"
}

test_false_group_does_not_abort_a_sourced_module() {
  local out
  out=$(bash -c "set -euo pipefail; DUCAL_ROOT='$ROOT'; source '$ROOT/lib/common.sh'; source '$ROOT/lib/groups.sh'; DUCAL_GROUPS_SELECTED=''; (source '$ROOT/install/50-system.sh'); echo rc=\$?" 2>/dev/null | tail -1)
  assert_eq "$out" "rc=0"
}

test_wsl_drops_desktop_extras_with_a_warning() {
  local out
  out=$(DUCAL_WSL=1 DUCAL_EXTRAS=chrome,go,steam groups 'select_install; echo "$DUCAL_EXTRAS"' 2>"$SANDBOX/err")
  assert_eq "$out" "go"
  assert_contains "$SANDBOX/err" "chrome is not available on WSL"
  assert_eq "$(DUCAL_WSL=1 DUCAL_EXTRAS=all groups 'select_install; echo "$DUCAL_EXTRAS"' 2>/dev/null)" "node,go,rust,docker"
}

test_config_module_does_not_theme_the_terminal_when_it_is_not_chosen() {
  DUCAL_GROUPS_SELECTED="languages" "$ROOT/install.sh" --only config >/dev/null 2>&1
  [[ ! -e $HOME/.config/starship.toml ]] || fail "terminal themed without the terminal group"
}

test_install_rejects_an_unknown_profile() {
  local err; err=$("$ROOT/install.sh" --profile gaming 2>&1); local rc=$?
  assert_eq "$rc" "1"
  [[ $err == *"Unknown profile: gaming"* ]] || fail "message: $err"
}

test_claude_is_skipped_when_already_installed() {
  stub_package_tools
  fake_cmd claude
  bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; install_claude" >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_not_contains "$STUB_LOG" "curl"
}

test_claude_uses_the_official_installer_when_missing() {
  stub_package_tools
  # The installer script served by the curl stub only records that it ran
  printf '#!/usr/bin/env bash\necho "curl $*" >> "%s"\necho "echo claude-installer-ran >> %s"\n' "$STUB_LOG" "$STUB_LOG" > "$SANDBOX/stubs/curl"
  chmod +x "$SANDBOX/stubs/curl"
  # Keep any real claude on the host PATH out of the sandbox
  PATH="$SANDBOX/stubs:/usr/bin:/bin" bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; install_claude" >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$STUB_LOG" "curl -fsSL https://claude.ai/install.sh"
  assert_contains "$STUB_LOG" "claude-installer-ran"
}

# Stub fnm binary at $1 that logs its calls.
write_fnm_stub() {
  mkdir -p "$(dirname "$1")"
  printf '#!/usr/bin/env bash\necho "fnm $*" >> "%s"\n' "$STUB_LOG" > "$1"
  chmod +x "$1"
}

test_node_extra_skips_existing_fnm_and_exposes_node_to_the_session() {
  stub_package_tools
  local fnm_dir="$HOME/.local/share/fnm"
  write_fnm_stub "$fnm_dir/fnm"
  mkdir -p "$fnm_dir/aliases/default/bin"
  bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; install_extra_node" >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_not_contains "$STUB_LOG" "curl"
  assert_not_contains "$STUB_LOG" "fnm install"
  # Non-interactive programs (editors, MCP servers, AI agents) get Node from the session environment
  assert_contains "$HOME/.config/environment.d/60-ducal-node.conf" 'PATH=${HOME}/.local/share/fnm/aliases/default/bin:${PATH}'
}

test_node_extra_installs_the_claude_status_line_tool() {
  stub_package_tools
  local bin="$HOME/.local/share/fnm/aliases/default/bin"
  write_fnm_stub "$HOME/.local/share/fnm/fnm"
  mkdir -p "$bin"
  printf '#!/usr/bin/env bash\necho "npm $*" >> "%s"\n' "$STUB_LOG" > "$bin/npm"; chmod +x "$bin/npm"
  bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; install_extra_node" >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$STUB_LOG" "npm install -g ccstatusline@2.2.34"
  # already installed: not reinstalled
  : > "$STUB_LOG"; printf '#!/usr/bin/env bash\n' > "$bin/ccstatusline"; chmod +x "$bin/ccstatusline"
  bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; install_extra_node" >/dev/null 2>&1
  assert_not_contains "$STUB_LOG" "npm install"
}

# An fnm Node with ccstatusline already installed, so install_extra_node does nothing.
stub_installed_node() {
  local bin="$HOME/.local/share/fnm/aliases/default/bin"
  write_fnm_stub "$HOME/.local/share/fnm/fnm"
  mkdir -p "$bin"
  printf '#!/usr/bin/env bash\necho "npm $*" >> "%s"\n' "$STUB_LOG" > "$bin/npm"
  printf '#!/usr/bin/env bash\n' > "$bin/ccstatusline"
  chmod +x "$bin/npm" "$bin/ccstatusline"
}

# claude stub: logs calls; `mcp get NAME` succeeds and `plugin list` shows the
# plugin only when NAME is listed in $SANDBOX/claude-has.
stub_claude_cli() {
  : > "$SANDBOX/claude-has"
  cat > "$SANDBOX/stubs/claude" <<EOF
#!/usr/bin/env bash
echo "claude \$*" >> "\$STUB_LOG"
case "\$1 \$2" in
  "mcp get") grep -qx "\$3" "$SANDBOX/claude-has" ;;
  "plugin list") cat "$SANDBOX/claude-has" ;;
esac
EOF
  chmod +x "$SANDBOX/stubs/claude"
}

# curl stub serving the latest release of the Gentleman-Programming tools
stub_gentleman_releases() {
  local name
  for name in engram gentle-ai; do
    mkdir -p "$SANDBOX/rel-$name"
    printf '#!/usr/bin/env bash\necho "%s fixture"\n' "$name" > "$SANDBOX/rel-$name/$name"
    chmod +x "$SANDBOX/rel-$name/$name"
    tar -czf "$SANDBOX/$name.tar.gz" -C "$SANDBOX/rel-$name" "$name"
  done
  cat > "$SANDBOX/stubs/curl" <<EOF
#!/usr/bin/env bash
echo "curl \$*" >> "\$STUB_LOG"
r=https://github.com/Gentleman-Programming
case "\${@: -1}" in
  \$r/engram/releases/latest) printf '%s' \$r/engram/releases/tag/v3.7.2 ;;
  \$r/gentle-ai/releases/latest) printf '%s' \$r/gentle-ai/releases/tag/v5.0.0 ;;
  \$r/engram/releases/download/v3.7.2/engram_3.7.2_linux_amd64.tar.gz) cp "$SANDBOX/engram.tar.gz" "\${@: -2:1}" ;;
  \$r/gentle-ai/releases/download/v5.0.0/gentle-ai_5.0.0_linux_amd64.tar.gz) cp "$SANDBOX/gentle-ai.tar.gz" "\${@: -2:1}" ;;
  *) exit 22 ;;
esac
EOF
  chmod +x "$SANDBOX/stubs/curl"
}

test_claude_setup_installs_tools_plugins_and_mcp_servers() {
  stub_package_tools
  stub_installed_node
  stub_claude_cli
  stub_gentleman_releases
  PATH="$SANDBOX/stubs:/usr/bin:/bin" bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; setup_claude_code" >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_eq "$("$HOME/.local/bin/engram")" "engram fixture"
  assert_eq "$("$HOME/.local/bin/gentle-ai")" "gentle-ai fixture"
  assert_contains "$STUB_LOG" "npm install -g @colbymchenry/codegraph@1.6.3"
  assert_contains "$STUB_LOG" "claude plugin marketplace add Gentleman-Programming/engram"
  assert_contains "$STUB_LOG" "claude plugin install -s user engram@engram"
  assert_contains "$STUB_LOG" "claude plugin marketplace add warpdotdev/claude-code-warp"
  assert_contains "$STUB_LOG" "claude plugin install -s user warp@claude-code-warp"
  assert_contains "$STUB_LOG" "claude mcp add -s user codegraph -- codegraph serve --mcp"
  assert_contains "$STUB_LOG" "claude mcp add -s user context7 -- npx -y --package=@upstash/context7-mcp@2.2.5 -- context7-mcp"
  assert_contains "$STUB_LOG" "claude mcp add -s user engram -- $HOME/.local/bin/engram mcp --tools=agent"
  # without STITCH_API_KEY, stitch gets a placeholder key to replace later
  assert_contains "$STUB_LOG" "claude mcp add -s user stitch --transport http https://stitch.googleapis.com/mcp --header X-Goog-Api-Key: YOUR_STITCH_API_KEY"
}

test_claude_setup_adds_stitch_with_an_api_key_and_skips_what_exists() {
  stub_package_tools
  stub_installed_node
  stub_claude_cli
  for c in engram gentle-ai codegraph; do fake_cmd "$c"; done
  printf '%s\n' engram@engram warp@claude-code-warp codegraph context7 engram > "$SANDBOX/claude-has"
  PATH="$SANDBOX/stubs:/usr/bin:/bin" STITCH_API_KEY=k123 bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; setup_claude_code" >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_not_contains "$STUB_LOG" "curl"
  assert_not_contains "$STUB_LOG" "npm install"
  assert_not_contains "$STUB_LOG" "plugin install"
  assert_not_contains "$STUB_LOG" "mcp add -s user codegraph"
  assert_contains "$STUB_LOG" "claude mcp add -s user stitch --transport http https://stitch.googleapis.com/mcp --header X-Goog-Api-Key: k123"
}

test_claude_setup_keeps_an_existing_stitch_server() {
  stub_package_tools
  stub_installed_node
  stub_claude_cli
  for c in engram gentle-ai codegraph; do fake_cmd "$c"; done
  echo stitch > "$SANDBOX/claude-has"
  PATH="$SANDBOX/stubs:/usr/bin:/bin" STITCH_API_KEY=k123 bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; setup_claude_code" >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_not_contains "$STUB_LOG" "mcp add -s user stitch"
}

test_claude_setup_warns_and_continues_when_claude_is_missing() {
  stub_package_tools
  local err
  err=$(PATH="$SANDBOX/stubs:/usr/bin:/bin" bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; setup_claude_code" 2>&1 >/dev/null); local rc=$?
  assert_eq "$rc" "0"
  [[ $err == *"Claude Code CLI not found"* ]] || fail "message: $err"
}

test_node_extra_installs_fnm_and_lts_when_missing() {
  stub_package_tools
  local fnm_dir="$HOME/.local/share/fnm"
  # The fnm installer script (served by the curl stub) drops a stub fnm binary
  {
    echo "$(declare -f write_fnm_stub)"
    echo "STUB_LOG='$STUB_LOG'; write_fnm_stub '$fnm_dir/fnm'"
  } > "$SANDBOX/fnm-install.sh"
  printf '#!/usr/bin/env bash\necho "curl $*" >> "%s"\ncat "%s"\n' "$STUB_LOG" "$SANDBOX/fnm-install.sh" > "$SANDBOX/stubs/curl"
  chmod +x "$SANDBOX/stubs/curl"
  bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; install_extra_node" >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$STUB_LOG" "curl -fsSL https://fnm.vercel.app/install"
  assert_contains "$STUB_LOG" "fnm install --lts"
  assert_contains "$STUB_LOG" "fnm default lts-latest"
  assert_contains "$HOME/.config/environment.d/60-ducal-node.conf" 'aliases/default/bin'
}

test_theme_apply_colors_the_workspace_bar() {
  "$ROOT/bin/ducal" theme gruvbox >/dev/null 2>&1
  local p=/org/gnome/shell/extensions/space-bar/appearance
  assert_contains "$STUB_LOG" "dconf write $p/active-workspace-background-color '#7daea3'"
  assert_contains "$STUB_LOG" "dconf write $p/active-workspace-text-color '#282828'"
  assert_contains "$STUB_LOG" "dconf write $p/inactive-workspace-text-color '#d4be98'"
  assert_contains "$STUB_LOG" "dconf write $p/empty-workspace-text-color '#7c6f64'"
  # Workspaces with windows get a filled chip so they stand out from empty ones
  assert_contains "$STUB_LOG" "dconf write $p/inactive-workspace-background-color '#665c54'"
  assert_contains "$STUB_LOG" "dconf write $p/empty-workspace-background-color 'rgba(0,0,0,0)'"
}

test_keys_shows_the_shortcut_guide() {
  local out
  out=$("$ROOT/bin/ducal" keys); local rc=$?
  assert_eq "$rc" "0"
  local k
  for k in "Super+Q" "Super+Space" "Super+B" "Super+Shift+1" "Ctrl+Alt+L" "Ctrl+Alt+T" "Super+C" "Ctrl+Shift+Enter"; do
    [[ $out == *"$k"* ]] || fail "guide misses $k"
  done
}

test_theme_apply_sets_yazi_flavor() {
  "$ROOT/bin/ducal" theme gruvbox >/dev/null 2>&1
  assert_contains "$HOME/.config/yazi/theme.toml" 'dark = "gruvbox-dark"'
}

# ---------------------------------------------------------------- gnome
# Stateful stubs: installed extensions in $SANDBOX/ext-installed, gsettings
# extension lists in $SANDBOX/enabled and $SANDBOX/disabled.
stub_gnome_tools() {
  local s="$SANDBOX/stubs"
  : > "$SANDBOX/ext-installed"
  echo "['ding@rastersoft.com', 'other@example.com']" > "$SANDBOX/enabled"
  echo "['forge@jmmaranan.com']" > "$SANDBOX/disabled"
  printf '#!/usr/bin/env bash\necho "GNOME Shell 46.0"\n' > "$s/gnome-shell"
  cat > "$s/gnome-extensions" <<EOF
#!/usr/bin/env bash
echo "gnome-extensions \$*" >> "\$STUB_LOG"
[[ \$1 == list ]] && cat "$SANDBOX/ext-installed"
exit 0
EOF
  cat > "$s/gsettings" <<EOF
#!/usr/bin/env bash
echo "gsettings \$*" >> "\$STUB_LOG"
key=\${3:-}
f="$SANDBOX/\${key%-extensions}"
if [[ \$2 == org.gnome.shell && \$key == *-extensions ]]; then
  [[ \$1 == get ]] && cat "\$f"
  [[ \$1 == set ]] && echo "\$4" > "\$f"
fi
if [[ \$1 == get && \$key == toggle-application-view ]]; then
  cat "$SANDBOX/app-view" 2>/dev/null || echo "['<Super>a']"
fi
exit 0
EOF
  cat > "$s/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >> "$STUB_LOG"
# uuids listed in $SANDBOX/unavailable have no build at all; those in
# $SANDBOX/outdated only have builds for older GNOME Shells (the site still
# answers with one, like extensions.gnome.org does)
for a in "$@"; do [[ $a == *extension-info* ]] && grep -qF "$(sed 's/.*uuid=//; s/&.*//' <<<"$a")" "$(dirname "$STUB_LOG")/unavailable" 2>/dev/null && exit 22; done
for a in "$@"; do
  [[ $a == *extension-info* ]] || continue
  shells='"45": {"pk": 1}, "46": {"pk": 1}'
  grep -qF "$(sed 's/.*uuid=//; s/&.*//' <<<"$a")" "$(dirname "$STUB_LOG")/outdated" 2>/dev/null && shells='"44": {"pk": 1}, "45": {"pk": 1}'
  echo "{\"shell_version_map\": {$shells}, \"download_url\": \"/download-extension/x.shell-extension.zip?version_tag=1\"}"
  exit 0
done
out=""; while [[ $# -gt 0 ]]; do [[ $1 == -o ]] && out=$2; shift; done
[[ -n $out ]] && echo zip > "$out"
exit 0
EOF
  cat > "$s/dconf" <<EOF
#!/usr/bin/env bash
echo "dconf \$*" >> "\$STUB_LOG"
[[ \$1 == load ]] && cat > "$SANDBOX/dconf-loaded"
exit 0
EOF
  chmod +x "$s"/*
}

test_gnome_module_installs_only_missing_extensions() {
  stub_gnome_tools
  printf 'dash-to-dock@micxgx.gmail.com\nforge@jmmaranan.com\n' > "$SANDBOX/ext-installed"
  "$ROOT/install.sh" --only gnome >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$STUB_LOG" "uuid=search-light@icedman.github.com&shell_version=46"
  assert_contains "$STUB_LOG" "uuid=blur-my-shell@aunetx&shell_version=46"
  assert_not_contains "$STUB_LOG" "uuid=forge@jmmaranan.com"
  assert_not_contains "$STUB_LOG" "uuid=dash-to-dock@micxgx.gmail.com"
  assert_eq "$(grep -c 'gnome-extensions install --force' "$STUB_LOG")" "6" "6 missing extensions"
}

test_gnome_module_enables_ours_and_keeps_user_extensions() {
  stub_gnome_tools
  "$ROOT/install.sh" --only gnome >/dev/null 2>&1
  "$ROOT/install.sh" --only gnome >/dev/null 2>&1
  local enabled disabled
  enabled=$(cat "$SANDBOX/enabled"); disabled=$(cat "$SANDBOX/disabled")
  [[ $enabled == *"'other@example.com'"* ]] || fail "user extension dropped: $enabled"
  [[ $enabled == *"'forge@jmmaranan.com'"* && $enabled == *"'search-light@icedman.github.com'"* ]] || fail "missing ours: $enabled"
  [[ $enabled != *ding@rastersoft.com* ]] || fail "ding should be disabled: $enabled"
  assert_eq "$(grep -o 'forge@jmmaranan.com' <<<"$enabled" | wc -l)" "1" "no duplicates after two runs"
  [[ $disabled == *"'ubuntu-dock@ubuntu.com'"* && $disabled == *"'ding@rastersoft.com'"* ]] || fail "disabled: $disabled"
  [[ $disabled != *forge@jmmaranan.com* ]] || fail "forge must leave the disabled list: $disabled"
}

# A new GNOME often comes before every extension supports it: skip, do not stop
test_gnome_module_skips_an_extension_without_a_build() {
  stub_gnome_tools
  echo "search-light@icedman.github.com" > "$SANDBOX/unavailable"
  "$ROOT/install.sh" --only gnome >"$SANDBOX/out" 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$SANDBOX/out" "search-light@icedman.github.com is not available for GNOME Shell 46, skipping it"
  assert_contains "$SANDBOX/out" "Desktop settings applied"
  assert_eq "$(grep -c 'gnome-extensions install --force' "$STUB_LOG")" "7" "the other 7 extensions"
  [[ $(cat "$SANDBOX/enabled") != *search-light* ]] || fail "enabled: $(cat "$SANDBOX/enabled")"
}

# extensions.gnome.org answers with the newest build even when it does not support
# this GNOME Shell: GNOME then never loads it (Search Light on GNOME 50 and 51)
test_gnome_module_skips_an_extension_built_for_an_older_gnome() {
  stub_gnome_tools
  echo "search-light@icedman.github.com" > "$SANDBOX/outdated"
  "$ROOT/install.sh" --only gnome >"$SANDBOX/out" 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$SANDBOX/out" "search-light@icedman.github.com does not support GNOME Shell 46 yet, skipping it"
  assert_eq "$(grep -c 'gnome-extensions install --force' "$STUB_LOG")" "7" "the other 7 extensions"
  [[ $(cat "$SANDBOX/enabled") != *search-light* ]] || fail "enabled: $(cat "$SANDBOX/enabled")"
}

# An extension installed before a GNOME upgrade: replaced when a newer build
# supports this GNOME Shell, skipped otherwise
test_gnome_module_replaces_an_installed_extension_that_does_not_support_this_gnome() {
  stub_gnome_tools
  echo "search-light@icedman.github.com" > "$SANDBOX/ext-installed"
  local dir="$HOME/.local/share/gnome-shell/extensions/search-light@icedman.github.com"
  mkdir -p "$dir"
  echo '{"uuid": "search-light@icedman.github.com", "shell-version": ["44", "45"]}' > "$dir/metadata.json"
  "$ROOT/install.sh" --only gnome >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$STUB_LOG" "uuid=search-light@icedman.github.com&shell_version=46"
  assert_eq "$(grep -c 'gnome-extensions install --force' "$STUB_LOG")" "8" "search-light replaced"

  : > "$STUB_LOG"
  echo "search-light@icedman.github.com" > "$SANDBOX/outdated"
  "$ROOT/install.sh" --only gnome >"$SANDBOX/out" 2>&1
  assert_contains "$SANDBOX/out" "search-light@icedman.github.com does not support GNOME Shell 46 yet, skipping it"
}

# An installed extension that supports this GNOME Shell is not downloaded again
test_gnome_module_keeps_an_installed_extension_that_supports_this_gnome() {
  stub_gnome_tools
  echo "search-light@icedman.github.com" > "$SANDBOX/ext-installed"
  local dir="$HOME/.local/share/gnome-shell/extensions/search-light@icedman.github.com"
  mkdir -p "$dir"
  echo '{"uuid": "search-light@icedman.github.com", "shell-version": ["45", "46"]}' > "$dir/metadata.json"
  "$ROOT/install.sh" --only gnome >/dev/null 2>&1
  assert_not_contains "$STUB_LOG" "uuid=search-light@icedman.github.com"
}

# Without Search Light, Super+Space opens GNOME's own app search
test_gnome_module_puts_the_app_grid_on_super_space_without_search_light() {
  stub_gnome_tools
  echo "search-light@icedman.github.com" > "$SANDBOX/outdated"
  "$ROOT/install.sh" --only gnome >"$SANDBOX/out" 2>&1
  assert_contains "$STUB_LOG" "gsettings set org.gnome.shell.keybindings toggle-application-view ['<Super>a', '<Super>space']"
  assert_contains "$SANDBOX/out" "Super+Space opens the app grid"
}

# With Search Light back, the app grid gives Super+Space up again
test_gnome_module_gives_super_space_back_to_search_light() {
  stub_gnome_tools
  "$ROOT/install.sh" --only gnome >/dev/null 2>&1
  assert_not_contains "$STUB_LOG" "toggle-application-view ['<Super>a', '<Super>space']"
  assert_not_contains "$STUB_LOG" "gsettings reset org.gnome.shell.keybindings toggle-application-view"
  echo "['<Super>a', '<Super>space']" > "$SANDBOX/app-view"
  "$ROOT/install.sh" --only gnome >/dev/null 2>&1
  assert_contains "$STUB_LOG" "gsettings reset org.gnome.shell.keybindings toggle-application-view"
}

# Without dash-to-dock, Ubuntu's own dock stays on (it reads the same dock settings)
test_gnome_module_keeps_ubuntu_dock_without_dash_to_dock() {
  stub_gnome_tools
  echo "dash-to-dock@micxgx.gmail.com" > "$SANDBOX/unavailable"
  "$ROOT/install.sh" --only gnome >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  [[ $(cat "$SANDBOX/disabled") != *ubuntu-dock* ]] || fail "disabled: $(cat "$SANDBOX/disabled")"
  assert_not_contains "$STUB_LOG" "gnome-extensions disable ubuntu-dock@ubuntu.com"
  # no empty entry left behind: never `gnome-extensions disable` without a uuid
  ! grep -qxE 'gnome-extensions disable ?' "$STUB_LOG" || fail "disable ran without a uuid"
  assert_contains "$SANDBOX/dconf-loaded" "dock-position='BOTTOM'"
}

# Ubuntu 25.04+ picks the Ctrl+Alt+T terminal from ubuntu-xdg-terminals.list
test_gnome_module_makes_kitty_the_xdg_terminal_and_keeps_other_entries() {
  stub_gnome_tools
  mkdir -p "$HOME/.config"
  printf 'org.gnome.Ptyxis.desktop:new-window\nkitty.desktop\n' > "$HOME/.config/ubuntu-xdg-terminals.list"
  "$ROOT/install.sh" --only gnome >/dev/null 2>&1; local rc=$?
  "$ROOT/install.sh" --only gnome >/dev/null 2>&1
  assert_eq "$rc" "0"
  assert_eq "$(cat "$HOME/.config/ubuntu-xdg-terminals.list")" "$(printf 'kitty.desktop\norg.gnome.Ptyxis.desktop:new-window')"
  assert_contains "$STUB_LOG" "gsettings set org.gnome.desktop.default-applications.terminal exec $HOME/.local/bin/kitty"
}

# Search Light joins each shortcut list into ONE accelerator: two entries in one
# key became the invalid "<Super>space<Control>space" (only Ctrl+Super+Space worked)
test_gnome_module_gives_search_light_one_shortcut_per_key() {
  stub_gnome_tools
  "$ROOT/install.sh" --only gnome >/dev/null 2>&1
  assert_contains "$SANDBOX/dconf-loaded" "shortcut-search=['<Super>space']"
  assert_contains "$SANDBOX/dconf-loaded" "secondary-shortcut-search=['<Control>space']"
  assert_not_contains "$SANDBOX/dconf-loaded" "shortcut-search=['<Super>space', '<Control>space']"
}

# Clipboard history: Clipboard Indicator, 50 items with images, on Super+Shift+V
# (Super+V stays Forge's vertical split)
test_gnome_module_sets_up_clipboard_history() {
  stub_gnome_tools
  "$ROOT/install.sh" --only gnome >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$STUB_LOG" "uuid=clipboard-indicator@tudmotu.com&shell_version=46"
  [[ $(cat "$SANDBOX/enabled") == *"'clipboard-indicator@tudmotu.com'"* ]] || fail "not enabled: $(cat "$SANDBOX/enabled")"
  assert_contains "$SANDBOX/dconf-loaded" "[org/gnome/shell/extensions/clipboard-indicator]"
  assert_contains "$SANDBOX/dconf-loaded" "history-size=50"
  assert_contains "$SANDBOX/dconf-loaded" "cache-images=true"
  assert_contains "$SANDBOX/dconf-loaded" "toggle-menu=['<Shift><Super>v']"
}

# Keyboards with a screenshot key (Logitech K950) send Super+Shift+S, which Forge
# took for its stacked layout: the screenshot UI never opened
test_gnome_module_keeps_super_shift_s_for_screenshots() {
  stub_gnome_tools
  "$ROOT/install.sh" --only gnome >/dev/null 2>&1
  assert_contains "$SANDBOX/dconf-loaded" "show-screenshot-ui=['Print', '<Shift><Super>s']"
  assert_contains "$SANDBOX/dconf-loaded" "con-stacked-layout-toggle=['<Control><Super>s']"
}

test_gnome_module_loads_desktop_settings() {
  stub_gnome_tools
  "$ROOT/install.sh" --only gnome >/dev/null 2>&1
  assert_contains "$STUB_LOG" "dconf load /"
  assert_contains "$SANDBOX/dconf-loaded" "screensaver=['<Control><Alt>l']"
  assert_contains "$SANDBOX/dconf-loaded" "[org/gnome/shell/extensions/dash-to-dock]"
  assert_not_contains "$SANDBOX/dconf-loaded" "DP-4"
  # Numbered workspaces: Super+N goes there, Super+Shift+N sends the window
  assert_contains "$SANDBOX/dconf-loaded" "dynamic-workspaces=false"
  assert_contains "$SANDBOX/dconf-loaded" "switch-to-workspace-2=['<Super>2']"
  assert_contains "$SANDBOX/dconf-loaded" "move-to-workspace-4=['<Super><Shift>4']"
  assert_contains "$SANDBOX/dconf-loaded" "switch-to-application-1=@as []"
  # Super+number never opens apps, even beyond the four workspaces
  assert_contains "$SANDBOX/dconf-loaded" "switch-to-application-9=@as []"
  assert_contains "$SANDBOX/dconf-loaded" "app-hotkey-10=@as []"
  assert_contains "$SANDBOX/dconf-loaded" "app-hotkey-5=@as []"
  # Super+Q closes windows (Alt+F4 still works); the dock no longer reserves it
  assert_contains "$SANDBOX/dconf-loaded" "close=['<Super>q', '<Alt>F4']"
  assert_contains "$SANDBOX/dconf-loaded" "shortcut=@as []"
  # GNOME vs Forge clashes resolved: Super+V and Ctrl+Alt+D go to Forge,
  # Ctrl+Alt+T opens the terminal and Forge's right two-thirds moves to Ctrl+Alt+R
  assert_contains "$SANDBOX/dconf-loaded" "toggle-message-tray=['<Super>m']"
  assert_contains "$SANDBOX/dconf-loaded" "show-desktop=['<Primary><Super>d', '<Super>d']"
  assert_contains "$SANDBOX/dconf-loaded" "window-snap-two-third-right=['<Ctrl><Alt>r']"
  assert_contains "$STUB_LOG" "gsettings set org.gnome.desktop.default-applications.terminal exec $HOME/.local/bin/kitty"
  assert_contains "$SANDBOX/dconf-loaded" "hot-keys=false"
  assert_contains "$SANDBOX/dconf-loaded" "enable-activate-workspace-shortcuts=false"
  assert_contains "$STUB_LOG" "uuid=space-bar@luchrioh"
}

# ---------------------------------------------------------------- assets
# git clone creates a repo whose install.sh only logs; curl writes the -o file.
stub_asset_tools() {
  stub_package_tools
  local s="$SANDBOX/stubs"
  cat > "$s/git" <<'EOF'
#!/usr/bin/env bash
echo "git $*" >> "$STUB_LOG"
dest="${@: -1}"
mkdir -p "$dest/themes" "$dest/dist-white"
printf '#!/usr/bin/env bash\necho "upstream-install %s $*" >> "$STUB_LOG"\n' "$(basename "$dest")" > "$dest/themes/install.sh"
cp "$dest/themes/install.sh" "$dest/install.sh"
chmod +x "$dest/themes/install.sh" "$dest/install.sh"
echo cursor > "$dest/dist-white/index.theme"
EOF
  cat > "$s/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >> "$STUB_LOG"
out=""; while [[ $# -gt 0 ]]; do [[ $1 == -o ]] && out=$2; shift; done
[[ -n $out ]] && echo image > "$out"
exit 0
EOF
  chmod +x "$s/git" "$s/curl"
}

test_assets_module_installs_themes_icons_and_cursors() {
  stub_asset_tools
  "$ROOT/install.sh" --only assets >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$STUB_LOG" "Fausto-Korpsvart/Tokyonight-GTK-Theme"
  assert_contains "$STUB_LOG" "Fausto-Korpsvart/Gruvbox-GTK-Theme"
  assert_contains "$STUB_LOG" "upstream-install Tela-circle-icon-theme"
  assert_contains "$HOME/.icons/Vimix-white-cursors/index.theme" "cursor"
  assert_contains "$HOME/.icons/default/index.theme" "Inherits=Vimix-white-cursors"
  assert_eq "$(cat "$HOME/.config/ducal/current" 2>/dev/null)" "tokyo-night" "default theme applied"
}

test_assets_module_skips_what_is_already_installed() {
  stub_asset_tools
  mkdir -p "$HOME/.themes/Tokyonight-Dark" "$HOME/.themes/Gruvbox-Dark" "$HOME/.local/share/icons/Tela-circle-dark" \
    "$HOME/.icons/Vimix-white-cursors" "$HOME/.config/ducal"
  echo gruvbox > "$HOME/.config/ducal/current"
  "$ROOT/install.sh" --only assets >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_not_contains "$STUB_LOG" "git clone"
  assert_not_contains "$STUB_LOG" "curl"
  assert_eq "$(cat "$HOME/.config/ducal/current")" "gruvbox" "user's theme kept"
}

# ---------------------------------------------------------------- system
# A fake system root with the files the system module reads; sudo runs the
# command as is and every system-changing command only logs.
setup_sysroot() {
  stub_package_tools
  export DUCAL_SYSROOT="$SANDBOX/root"
  local r=$DUCAL_SYSROOT s="$SANDBOX/stubs" c
  mkdir -p "$r/usr/share/gnome-shell/theme/Yaru" "$r/usr/share/plymouth/themes/spinner" "$r/etc/gdm3"
  cp /usr/share/gnome-shell/theme/Yaru/gnome-shell-theme.gresource "$r/usr/share/gnome-shell/theme/Yaru/"
  for f in animation-0001 throbber-0001 bullet entry lock capslock keyboard keymap-render; do
    echo png > "$r/usr/share/plymouth/themes/spinner/$f.png"
  done
  printf '[org/gnome/login-screen]\n#logo=%s\n\n[org/gnome/desktop/interface]\n' "'/x.png'" > "$r/etc/gdm3/greeter.dconf-defaults"
  printf 'NAME="Ubuntu"\nVERSION="24.04.5 LTS (Noble Numbat)"\nID=ubuntu\n' > "$r/etc/os-release"
  for c in update-alternatives update-initramfs dpkg-reconfigure; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "$STUB_LOG"\n' "$c" > "$s/$c"
  done
  chmod +x "$s"/*
  # GTK theme the login screen builds on
  mkdir -p "$HOME/.themes/Tokyonight-Dark/gnome-shell/assets"
  printf '.a { background: url("assets/x.svg"); }\n.b { background: url("resource:///org/gnome/shell/theme/gnome-shell-start.svg"); }\n' \
    > "$HOME/.themes/Tokyonight-Dark/gnome-shell/gnome-shell.css"
  echo '<svg/>' > "$HOME/.themes/Tokyonight-Dark/gnome-shell/assets/x.svg"
  printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 25"><rect width="100" height="25"/></svg>\n' > "$SANDBOX/logo.svg"
}

gdm_css() { gresource extract "$DUCAL_SYSROOT/usr/share/gnome-shell/theme/ducal/gnome-shell-theme.gresource" /org/gnome/shell/theme/gdm.css; }

test_system_install_with_logo_themes_login_and_boot() {
  setup_sysroot
  DUCAL_SYSTEM=yes DUCAL_LOGO="$SANDBOX/logo.svg" "$ROOT/install.sh" --only system >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  local r=$DUCAL_SYSROOT
  gdm_css > "$SANDBOX/gdm.css" 2>/dev/null || fail "gresource missing or unreadable"
  assert_contains "$SANDBOX/gdm.css" "#lockDialogGroup { background-color: #1a1b26; }"
  assert_contains "$SANDBOX/gdm.css" ".login-dialog StEntry:focus {"
  assert_not_contains "$SANDBOX/gdm.css" ".login-dialog StEntry, .unlock-dialog StEntry:focus"
  assert_not_contains "$SANDBOX/gdm.css" "{{"
  gresource list "$r/usr/share/gnome-shell/theme/ducal/gnome-shell-theme.gresource" > "$SANDBOX/res"
  assert_contains "$SANDBOX/res" "/org/gnome/shell/theme/assets/x.svg"
  assert_contains "$SANDBOX/res" "/org/gnome/shell/theme/gnome-shell-start.svg"
  assert_contains "$STUB_LOG" "update-alternatives --set gdm-theme.gresource $r/usr/share/gnome-shell/theme/ducal/gnome-shell-theme.gresource"
  assert_contains "$r/etc/gdm3/greeter.dconf-defaults" "logo='$r/usr/share/pixmaps/ducal-logo.svg'"
  assert_contains "$r/usr/share/pixmaps/ducal-logo.svg" "24.04.5 LTS"
  assert_not_contains "$r/usr/share/pixmaps/ducal-logo.svg" 'id="ducal-mark"' "DUCAL_LOGO replaces the ducal mark"
  assert_contains "$r/etc/gdm3/greeter.dconf-defaults.ducal-logo-line" "#logo='/x.png'"
  assert_contains "$STUB_LOG" "dpkg-reconfigure gdm3"
  local p="$r/usr/share/plymouth/themes/ducal"
  assert_contains "$p/ducal.plymouth" "BackgroundStartColor=0x1a1b26"
  assert_contains "$p/ducal.plymouth" "ImageDir=/usr/share/plymouth/themes/ducal"
  [[ -s $p/watermark.png && -f $p/throbber-0001.png ]] || fail "plymouth images missing"
  assert_contains "$STUB_LOG" "update-alternatives --set default.plymouth $p/ducal.plymouth"
  assert_contains "$STUB_LOG" "update-initramfs -u"
  # Build tools a fresh Ubuntu (26.04) does not ship, installed first
  assert_contains "$STUB_LOG" "apt-get install -y libglib2.0-bin libglib2.0-dev-bin python3-gi gir1.2-gdkpixbuf-2.0 librsvg2-common plymouth-theme-spinner"
}

test_system_install_skips_build_tools_already_installed() {
  setup_sysroot
  printf '%s\n' libglib2.0-bin libglib2.0-dev-bin python3-gi gir1.2-gdkpixbuf-2.0 librsvg2-common plymouth-theme-spinner > "$SANDBOX/installed"
  DUCAL_SYSTEM=yes "$ROOT/install.sh" --only system >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_not_contains "$STUB_LOG" "apt-get install"
}

test_system_install_without_logo_uses_the_ducal_mark() {
  setup_sysroot
  DUCAL_SYSTEM=yes "$ROOT/install.sh" --only system >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  local r=$DUCAL_SYSROOT
  assert_contains "$r/etc/gdm3/greeter.dconf-defaults" "logo='$r/usr/share/pixmaps/ducal-logo.svg'"
  # The mark is painted with the active theme's accent, next to the distribution name
  assert_contains "$r/usr/share/pixmaps/ducal-logo.svg" 'id="ducal-mark"'
  assert_contains "$r/usr/share/pixmaps/ducal-logo.svg" 'fill="#7aa2f7"'
  assert_contains "$r/usr/share/pixmaps/ducal-logo.svg" "24.04.5 LTS"
  assert_not_contains "$r/usr/share/pixmaps/ducal-logo.svg" "{{"
  [[ -s $r/usr/share/plymouth/themes/ducal/watermark.png ]] || fail "boot splash watermark missing"
}

test_system_install_twice_keeps_the_original_logo_line() {
  setup_sysroot
  DUCAL_SYSTEM=yes DUCAL_LOGO="$SANDBOX/logo.svg" "$ROOT/install.sh" --only system >/dev/null 2>&1
  DUCAL_SYSTEM=yes DUCAL_LOGO="$SANDBOX/logo.svg" "$ROOT/install.sh" --only system >/dev/null 2>&1
  assert_eq "$(grep -c 'logo=' "$DUCAL_SYSROOT/etc/gdm3/greeter.dconf-defaults")" "1"
  "$ROOT/bin/ducal" system restore >/dev/null 2>&1
  assert_contains "$DUCAL_SYSROOT/etc/gdm3/greeter.dconf-defaults" "#logo='/x.png'"
}

test_system_logo_with_namespaced_svg_is_composed() {
  setup_sysroot
  printf '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 10 10"><defs><rect id="r" width="5" height="5"/></defs><use xlink:href="#r"/></svg>\n' > "$SANDBOX/inkscape.svg"
  DUCAL_SYSTEM=yes DUCAL_LOGO="$SANDBOX/inkscape.svg" "$ROOT/install.sh" --only system >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  python3 -c "import sys,xml.dom.minidom as m; m.parse(sys.argv[1])" "$DUCAL_SYSROOT/usr/share/pixmaps/ducal-logo.svg" 2>/dev/null ||
    fail "composed logo is not valid XML"
}

test_system_reinstall_without_logo_goes_back_to_the_ducal_mark() {
  setup_sysroot
  DUCAL_SYSTEM=yes DUCAL_LOGO="$SANDBOX/logo.svg" "$ROOT/install.sh" --only system >/dev/null 2>&1
  DUCAL_SYSTEM=yes "$ROOT/install.sh" --only system >/dev/null 2>&1
  local r=$DUCAL_SYSROOT
  assert_contains "$r/usr/share/pixmaps/ducal-logo.svg" 'id="ducal-mark"'
  assert_eq "$(grep -c 'logo=' "$r/etc/gdm3/greeter.dconf-defaults")" "1"
  # The distribution's original line is still the one restore puts back
  assert_contains "$r/etc/gdm3/greeter.dconf-defaults.ducal-logo-line" "#logo='/x.png'"
  "$ROOT/bin/ducal" system restore >/dev/null 2>&1
  assert_contains "$r/etc/gdm3/greeter.dconf-defaults" "#logo='/x.png'"
  [[ ! -e $r/usr/share/pixmaps/ducal-logo.svg ]] || fail "logo file left behind after restore"
}

test_system_restore_puts_back_an_active_distro_logo_line() {
  setup_sysroot
  local r=$DUCAL_SYSROOT g="$DUCAL_SYSROOT/etc/gdm3/greeter.dconf-defaults"
  printf '[org/gnome/login-screen]\nlogo=%s\n' "'/usr/share/pixmaps/distro.png'" > "$g"
  DUCAL_SYSTEM=yes "$ROOT/install.sh" --only system >/dev/null 2>&1
  DUCAL_SYSTEM=yes DUCAL_LOGO="$SANDBOX/logo.svg" "$ROOT/install.sh" --only system >/dev/null 2>&1
  DUCAL_SYSTEM=yes "$ROOT/install.sh" --only system >/dev/null 2>&1
  "$ROOT/bin/ducal" system restore >/dev/null 2>&1
  assert_eq "$(grep 'logo=' "$g")" "logo='/usr/share/pixmaps/distro.png'"
  [[ ! -e $r/usr/share/pixmaps/ducal-logo.svg && ! -e $g.ducal-logo-line ]] || fail "ducal files left behind"
}

test_system_install_with_a_missing_logo_changes_nothing() {
  setup_sysroot
  cp "$DUCAL_SYSROOT/etc/gdm3/greeter.dconf-defaults" "$SANDBOX/greeter.before"
  DUCAL_SYSTEM=yes DUCAL_LOGO="$SANDBOX/nope.svg" "$ROOT/install.sh" --only system >/dev/null 2>&1; local rc=$?
  [[ $rc -ne 0 ]] || fail "expected a failure"
  cmp -s "$SANDBOX/greeter.before" "$DUCAL_SYSROOT/etc/gdm3/greeter.dconf-defaults" || fail "greeter changed"
  assert_not_contains "$STUB_LOG" "update-alternatives"
  assert_not_contains "$STUB_LOG" "update-initramfs"
}

test_system_restore_cleans_up_after_an_interrupted_install() {
  setup_sysroot
  local r=$DUCAL_SYSROOT
  # The install stopped after saving the original line and the logo, before editing the greeter
  mkdir -p "$r/usr/share/pixmaps"
  echo '<svg/>' > "$r/usr/share/pixmaps/ducal-logo.svg"
  echo "#logo='/x.png'" > "$r/etc/gdm3/greeter.dconf-defaults.ducal-logo-line"
  "$ROOT/bin/ducal" system restore >/dev/null 2>&1
  [[ ! -e $r/usr/share/pixmaps/ducal-logo.svg && ! -e $r/etc/gdm3/greeter.dconf-defaults.ducal-logo-line ]] || fail "ducal files left behind"
  assert_contains "$r/etc/gdm3/greeter.dconf-defaults" "#logo='/x.png'"
}

test_system_boot_watermark_is_640px_wide() {
  setup_sysroot
  DUCAL_SYSTEM=yes "$ROOT/install.sh" --only system >/dev/null 2>&1
  local w
  w=$(python3 -c "import struct,sys; d=open(sys.argv[1],'rb').read(24); print(struct.unpack('>I', d[16:20])[0])" \
    "$DUCAL_SYSROOT/usr/share/plymouth/themes/ducal/watermark.png" 2>/dev/null)
  assert_eq "$w" "640"
}

test_system_logo_line_is_added_when_missing() {
  setup_sysroot
  printf '[org/gnome/login-screen]\ndisable-user-list=false\n' > "$DUCAL_SYSROOT/etc/gdm3/greeter.dconf-defaults"
  DUCAL_SYSTEM=yes DUCAL_LOGO="$SANDBOX/logo.svg" "$ROOT/install.sh" --only system >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$DUCAL_SYSROOT/etc/gdm3/greeter.dconf-defaults" "logo='$DUCAL_SYSROOT/usr/share/pixmaps/ducal-logo.svg'"
  "$ROOT/bin/ducal" system restore >/dev/null 2>&1
  assert_not_contains "$DUCAL_SYSROOT/etc/gdm3/greeter.dconf-defaults" "logo="
}

test_system_bad_logo_fails_before_changing_the_system() {
  setup_sysroot
  echo "not an svg" > "$SANDBOX/bad.svg"
  DUCAL_SYSTEM=yes DUCAL_LOGO="$SANDBOX/bad.svg" "$ROOT/install.sh" --only system >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "1"
  assert_not_contains "$STUB_LOG" "update-alternatives"
}

test_system_restore_reports_failure() {
  setup_sysroot
  printf '#!/usr/bin/env bash\nexit 1\n' > "$SANDBOX/stubs/update-alternatives"
  "$ROOT/bin/ducal" system restore >/dev/null 2>&1; local rc=$?
  [[ $rc -ne 0 ]] || fail "restore must fail when a step fails"
}

test_system_module_does_nothing_unless_accepted() {
  setup_sysroot
  DUCAL_SYSTEM=no "$ROOT/install.sh" --only system >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_not_contains "$STUB_LOG" "update-alternatives"
  "$ROOT/install.sh" --only system </dev/null >/dev/null 2>&1
  assert_not_contains "$STUB_LOG" "update-alternatives"
}

test_system_restore_returns_to_ubuntu_defaults() {
  setup_sysroot
  DUCAL_SYSTEM=yes DUCAL_LOGO="$SANDBOX/logo.svg" "$ROOT/install.sh" --only system >/dev/null 2>&1
  : > "$STUB_LOG"
  "$ROOT/bin/ducal" system restore >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  local r=$DUCAL_SYSROOT
  assert_contains "$STUB_LOG" "update-alternatives --set gdm-theme.gresource $r/usr/share/gnome-shell/theme/Yaru/gnome-shell-theme.gresource"
  assert_contains "$STUB_LOG" "update-alternatives --set default.plymouth $r/usr/share/plymouth/themes/bgrt/bgrt.plymouth"
  assert_not_contains "$r/etc/gdm3/greeter.dconf-defaults" "ducal-logo"
  assert_contains "$STUB_LOG" "update-initramfs -u"
}

# ---------------------------------------------------------------- cleanup
stub_cleanup_tools() {
  stub_package_tools
  local s="$SANDBOX/stubs" c
  for c in snap systemctl; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "$STUB_LOG"\n[[ $1 == list ]] && echo "thunderbird"\n[[ $1 == is-enabled ]] && echo enabled\nexit 0\n' "$c" > "$s/$c"
  done
  chmod +x "$s"/*
}

test_cleanup_apps_removes_only_installed_packages() {
  stub_cleanup_tools
  printf 'rhythmbox\ngedit\nshowtime\n' > "$SANDBOX/installed"
  DUCAL_CLEANUP=apps "$ROOT/install.sh" --only cleanup >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  # showtime: the video player of Ubuntu 25.10 and newer
  assert_contains "$STUB_LOG" "apt-get remove -y rhythmbox showtime gedit"
  assert_not_contains "$STUB_LOG" "totem"
  assert_not_contains "$STUB_LOG" "autoremove"
}

test_cleanup_protects_desktop_packages_from_autoremove() {
  stub_cleanup_tools
  printf 'rhythmbox\ngnome-shell\nnautilus\n' > "$SANDBOX/installed"
    # Like the real apt-cache, answers in the system language unless LC_ALL=C
  cat > "$SANDBOX/stubs/apt-cache" <<'EOS'
#!/usr/bin/env bash
echo "apt-cache $*" >> "$STUB_LOG"
d=Depends r=Recommends; [[ ${LC_ALL:-} == C ]] || { d=Depende r=Recomienda; }
printf "ubuntu-desktop\n  $d: gnome-shell\n    gnome-shell:i386\n |$r: nautilus\n  $r: rhythmbox\n  $r: <virtual-thing>\n"
EOS
  printf '#!/usr/bin/env bash\necho "apt-mark $*" >> "$STUB_LOG"\n' > "$SANDBOX/stubs/apt-mark"
  chmod +x "$SANDBOX/stubs/apt-cache" "$SANDBOX/stubs/apt-mark"
  DUCAL_CLEANUP=apps "$ROOT/install.sh" --only cleanup >/dev/null 2>&1
  assert_contains "$STUB_LOG" "apt-mark manual gnome-shell nautilus"
  assert_not_contains "$STUB_LOG" "manual gnome-shell nautilus rhythmbox"
  local mark remove
  mark=$(grep -n 'apt-mark manual' "$STUB_LOG" | cut -d: -f1); remove=$(grep -n 'apt-get remove' "$STUB_LOG" | cut -d: -f1)
  [[ -n $mark && -n $remove && $mark -lt $remove ]] || fail "apt-mark must run before apt-get remove"
}

test_cleanup_office_removes_libreoffice_and_both_thunderbirds() {
  stub_cleanup_tools
  printf 'libreoffice-common\nlibreoffice-core\nthunderbird\n' > "$SANDBOX/installed"
  DUCAL_CLEANUP=office "$ROOT/install.sh" --only cleanup >/dev/null 2>&1
  assert_contains "$STUB_LOG" "apt-get remove -y libreoffice-common libreoffice-core thunderbird"
  assert_contains "$STUB_LOG" "snap remove thunderbird"
}

test_cleanup_telemetry_removes_reporting_tools() {
  stub_cleanup_tools
  printf 'ubuntu-report\nubuntu-insights\napport\nwhoopsie\nkerneloops\n' > "$SANDBOX/installed"
  DUCAL_CLEANUP=telemetry "$ROOT/install.sh" --only cleanup >/dev/null 2>&1
  # ubuntu-insights replaces ubuntu-report on Ubuntu 25.10 and newer
  assert_contains "$STUB_LOG" "apt-get remove -y ubuntu-report ubuntu-insights apport whoopsie kerneloops"
}

test_cleanup_services_are_disabled_not_removed() {
  stub_cleanup_tools
  printf 'cups\n' > "$SANDBOX/installed"
  DUCAL_CLEANUP=services "$ROOT/install.sh" --only cleanup >/dev/null 2>&1
  local u
  for u in cups.service cups.socket cups.path cups-browsed.service ModemManager.service avahi-daemon.service avahi-daemon.socket; do
    assert_contains "$STUB_LOG" "systemctl disable --now $u"
  done
  assert_contains "$STUB_LOG" "systemctl --user mask --now tracker-miner-fs-3.service"
  assert_not_contains "$STUB_LOG" "apt-get remove"
}

# GNOME 47+ renamed the file indexer to localsearch: mask the one this system has
test_cleanup_services_mask_only_the_indexer_this_release_has() {
  stub_cleanup_tools
  cat > "$SANDBOX/stubs/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >> "$STUB_LOG"
[[ $* == "--user list-unit-files tracker-miner-fs-3.service" ]] && exit 1
exit 0
EOF
  DUCAL_CLEANUP=services "$ROOT/install.sh" --only cleanup >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$STUB_LOG" "systemctl --user mask --now localsearch-3.service"
  assert_not_contains "$STUB_LOG" "mask --now tracker-miner-fs-3.service"
}

test_cleanup_does_nothing_by_default_without_a_terminal() {
  stub_cleanup_tools
  printf 'rhythmbox\n' > "$SANDBOX/installed"
  "$ROOT/install.sh" --only cleanup </dev/null >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_not_contains "$STUB_LOG" "apt-get remove"
  assert_not_contains "$STUB_LOG" "systemctl disable"
}

test_cleanup_rejects_unknown_group() {
  stub_cleanup_tools
  DUCAL_CLEANUP=apps,nope "$ROOT/install.sh" --only cleanup >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "1"
  assert_not_contains "$STUB_LOG" "apt-get remove"
}

test_cleanup_services_continue_when_one_unit_is_missing() {
  stub_cleanup_tools
  # cups-browsed is not installed: systemctl fails for it only
  printf '#!/usr/bin/env bash\necho "systemctl $*" >> "$STUB_LOG"\n[[ $* == *cups-browsed* ]] && exit 1\nexit 0\n' > "$SANDBOX/stubs/systemctl"
  DUCAL_CLEANUP=services "$ROOT/install.sh" --only cleanup >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$STUB_LOG" "systemctl disable --now cups.service"
  assert_contains "$STUB_LOG" "systemctl disable --now ModemManager.service"
}

test_cleanup_restore_services_reports_failure() {
  stub_cleanup_tools
  printf '#!/usr/bin/env bash\n[[ $1 == --user ]] && exit 1\nexit 0\n' > "$SANDBOX/stubs/systemctl"
  local out
  out=$("$ROOT/bin/ducal" cleanup restore-services 2>&1); local rc=$?
  [[ $rc -ne 0 ]] || fail "must fail when a unit cannot be restored"
  [[ $out != *"Services enabled again"* ]] || fail "must not report success: $out"
}

test_cleanup_restore_services_reenables_them() {
  stub_cleanup_tools
  "$ROOT/bin/ducal" cleanup restore-services >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$STUB_LOG" "systemctl enable --now cups.service"
  assert_contains "$STUB_LOG" "systemctl enable --now cups-browsed.service"
  assert_contains "$STUB_LOG" "systemctl --user unmask tracker-miner-fs-3.service"
  assert_contains "$STUB_LOG" "systemctl --user unmask localsearch-3.service"
}

# ---------------------------------------------------------------- wallpaper
make_png() {
  python3 -c "import zlib,struct,sys
def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
open(sys.argv[1],'wb').write(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1,1,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b'\x00\x00\x00\x00'))+chunk(b'IEND',b''))" "$1"
}

test_wallpaper_sets_a_copy_of_the_image() {
  make_png "$SANDBOX/mine.png"
  "$ROOT/bin/ducal" wallpaper "$SANDBOX/mine.png" >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  local copy="$HOME/.config/ducal/wallpaper.png"
  cmp -s "$copy" "$SANDBOX/mine.png" || fail "copy missing or different"
  assert_contains "$STUB_LOG" "gsettings set org.gnome.desktop.background picture-uri-dark file://$copy"
  rm "$SANDBOX/mine.png"
  "$ROOT/bin/ducal" wallpaper 2>&1 | grep -qF "$copy" || fail "status should show the custom wallpaper"
}

test_theme_switch_keeps_the_custom_wallpaper() {
  make_png "$SANDBOX/mine.png"
  "$ROOT/bin/ducal" wallpaper "$SANDBOX/mine.png" >/dev/null 2>&1
  : > "$STUB_LOG"
  "$ROOT/bin/ducal" theme gruvbox >/dev/null 2>&1
  assert_contains "$STUB_LOG" "picture-uri-dark file://$HOME/.config/ducal/wallpaper.png"
  assert_not_contains "$STUB_LOG" "ducal-gruvbox.svg"
}

test_theme_uses_a_wallpaper_generated_from_its_palette() {
  "$ROOT/bin/ducal" theme gruvbox >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  local w="$HOME/.local/share/ducal/wallpapers/ducal-gruvbox.svg"
  assert_contains "$w" 'fill="#282828"'
  assert_contains "$w" 'id="ducal-mark"'
  assert_contains "$w" 'fill="#7daea3"'
  assert_not_contains "$w" "{{"
  python3 -c "import sys; from xml.dom import minidom; minidom.parse(sys.argv[1])" "$w" 2>/dev/null || fail "wallpaper is not valid SVG"
  assert_contains "$STUB_LOG" "gsettings set org.gnome.desktop.background picture-uri-dark file://$w"
}

test_wallpaper_reset_returns_to_the_theme_wallpaper() {
  make_png "$SANDBOX/mine.png"
  "$ROOT/bin/ducal" theme gruvbox >/dev/null 2>&1
  "$ROOT/bin/ducal" wallpaper "$SANDBOX/mine.png" >/dev/null 2>&1
  : > "$STUB_LOG"
  "$ROOT/bin/ducal" wallpaper reset >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  [[ ! -e $HOME/.config/ducal/wallpaper.png ]] || fail "custom wallpaper should be removed"
  assert_contains "$STUB_LOG" "picture-uri-dark file://$HOME/.local/share/ducal/wallpapers/ducal-gruvbox.svg"
}

test_wallpaper_rejects_missing_and_non_image_files() {
  local err
  err=$("$ROOT/bin/ducal" wallpaper "$SANDBOX/nope.png" 2>&1); local rc=$?
  assert_eq "$rc" "1"
  [[ $err == *"not found"* ]] || fail "stderr: $err"
  echo "text" > "$SANDBOX/notes.png"
  err=$("$ROOT/bin/ducal" wallpaper "$SANDBOX/notes.png" 2>&1); rc=$?
  assert_eq "$rc" "1"
  [[ $err == *"not an image"* ]] || fail "stderr: $err"
  assert_not_contains "$STUB_LOG" "picture-uri"
}

# ---------------------------------------------------------------- search
# zenity answers with $SANDBOX/typed (or cancels when the file is missing)
stub_search_tools() {
  local s="$SANDBOX/stubs"
  printf '#!/usr/bin/env bash\necho "xdg-open $*" >> "$STUB_LOG"\n' > "$s/xdg-open"
  printf '#!/usr/bin/env bash\necho "zenity $*" >> "$STUB_LOG"\n[[ -f "%s/typed" ]] || exit 1\ncat "%s/typed"\n' "$SANDBOX" "$SANDBOX" > "$s/zenity"
  chmod +x "$s/xdg-open" "$s/zenity"
}

test_search_opens_the_browser_with_the_query() {
  stub_search_tools
  "$ROOT/bin/ducal" search "tokyo night & gruvbox" >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$STUB_LOG" "xdg-open https://www.google.com/search?q=tokyo+night+%26+gruvbox"
}

test_search_opens_addresses_directly() {
  stub_search_tools
  "$ROOT/bin/ducal" search "github.com/yusney/ducal" >/dev/null 2>&1
  "$ROOT/bin/ducal" search "http://localhost:3000" >/dev/null 2>&1
  assert_contains "$STUB_LOG" "xdg-open https://github.com/yusney/ducal"
  assert_contains "$STUB_LOG" "xdg-open http://localhost:3000"
}

test_search_without_query_asks_in_a_dialog() {
  stub_search_tools
  echo "neovim lazyvim" > "$SANDBOX/typed"
  "$ROOT/bin/ducal" search >/dev/null 2>&1
  assert_contains "$STUB_LOG" "xdg-open https://www.google.com/search?q=neovim+lazyvim"
}

test_search_dialog_cancel_or_empty_opens_nothing() {
  stub_search_tools
  "$ROOT/bin/ducal" search >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  echo "   " > "$SANDBOX/typed"
  "$ROOT/bin/ducal" search >/dev/null 2>&1
  assert_not_contains "$STUB_LOG" "xdg-open"
}

test_search_dialog_opens_only_once() {
  stub_search_tools
  echo "neovim" > "$SANDBOX/typed"
  local run="$SANDBOX/run"
  mkdir -p "$run"
  # an open dialog holds the lock, as a second Super+B press would find it
  exec 8>"$run/ducal-search.lock"
  flock -n 8 || fail "could not take the lock"
  XDG_RUNTIME_DIR=$run "$ROOT/bin/ducal" search >/dev/null 2>&1; local rc=$?
  exec 8>&-
  assert_eq "$rc" "0"
  assert_not_contains "$STUB_LOG" "zenity"
  assert_not_contains "$STUB_LOG" "xdg-open"
  # once the dialog is closed, Super+B opens it again
  XDG_RUNTIME_DIR=$run "$ROOT/bin/ducal" search >/dev/null 2>&1
  assert_contains "$STUB_LOG" "xdg-open https://www.google.com/search?q=neovim"
}

test_search_uses_a_custom_engine() {
  stub_search_tools
  mkdir -p "$HOME/.config/ducal"
  echo "https://duckduckgo.com/?q=%s" > "$HOME/.config/ducal/search-url"
  "$ROOT/bin/ducal" search "ubuntu" >/dev/null 2>&1
  assert_contains "$STUB_LOG" "xdg-open https://duckduckgo.com/?q=ubuntu"
}

test_gnome_module_adds_the_search_shortcut_once() {
  stub_gnome_tools
  cat > "$SANDBOX/stubs/gsettings" <<EOF
#!/usr/bin/env bash
echo "gsettings \$*" >> "\$STUB_LOG"
case "\$2 \$3" in
  "org.gnome.shell enabled-extensions") f="$SANDBOX/enabled" ;;
  "org.gnome.shell disabled-extensions") f="$SANDBOX/disabled" ;;
  "org.gnome.settings-daemon.plugins.media-keys custom-keybindings") f="$SANDBOX/custom" ;;
  *) exit 0 ;;
esac
[[ \$1 == get ]] && cat "\$f"
[[ \$1 == set ]] && echo "\$4" > "\$f"
exit 0
EOF
  chmod +x "$SANDBOX/stubs/gsettings"
  echo "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']" > "$SANDBOX/custom"
  "$ROOT/install.sh" --only gnome >/dev/null 2>&1
  "$ROOT/install.sh" --only gnome >/dev/null 2>&1
  local p=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ducal-search/
  assert_eq "$(cat "$SANDBOX/custom")" "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', '$p']"
  assert_contains "$STUB_LOG" "dconf write ${p}binding '<Super>b'"
  assert_contains "$STUB_LOG" "dconf write ${p}command '$HOME/.local/bin/ducal search'"
}

# ---------------------------------------------------------------- run
ORIG_PATH=$PATH
ORIG_HOME=$HOME
echo "ducal tests"
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do run_test "$t"; done
export HOME=$ORIG_HOME
echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
