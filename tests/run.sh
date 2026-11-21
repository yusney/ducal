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
  mkdir -p "$HOME" "$SANDBOX/stubs"
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

# ---------------------------------------------------------------- apps
# Stubs for package tools: sudo runs the command, apt-get/curl only log.
stub_package_tools() {
  local s="$SANDBOX/stubs"
  printf '#!/usr/bin/env bash\n"$@"\n' > "$s/sudo"
  printf '#!/usr/bin/env bash\necho "apt-get $*" >> "$STUB_LOG"\n' > "$s/apt-get"
  printf '#!/usr/bin/env bash\necho "curl $*" >> "$STUB_LOG"\nexit 1\n' > "$s/curl"
  # dpkg-query reports only the packages listed in $SANDBOX/installed as installed
  printf '#!/usr/bin/env bash\npkg="${@: -1}"\ngrep -qx "$pkg" "%s/installed" && echo "install ok installed" || exit 1\n' "$SANDBOX" > "$s/dpkg-query"
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
  assert_eq "$out" "chrome code docker go rust steam discord"
  out=$(bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; parse_extras none")
  assert_eq "$out" ""
}

test_parse_extras_rejects_unknown_names() {
  local err
  err=$(bash -c "source '$ROOT/lib/common.sh'; source '$ROOT/lib/apps.sh'; parse_extras 'chrome,nope'" 2>&1); local rc=$?
  assert_eq "$rc" "1"
  [[ $err == *"Unknown extra: nope"* ]] || fail "stderr: $err"
}

test_apps_module_skips_tools_already_installed() {
  stub_package_tools
  printf '%s\n' git curl unzip fontconfig build-essential fish btop ripgrep fd-find gh > "$SANDBOX/installed"
  for c in kitty nvim starship lazygit yazi ya fd; do fake_cmd "$c"; done
  mkdir -p "$HOME/.local/share/fonts/JetBrainsMonoNerd"
  DUCAL_EXTRAS=none "$ROOT/install.sh" --only apps >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_not_contains "$STUB_LOG" "curl"
  assert_not_contains "$STUB_LOG" "apt-get install"
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
exit 0
EOF
  cat > "$s/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >> "$STUB_LOG"
for a in "$@"; do [[ $a == *extension-info* ]] && { echo '{"download_url": "/download-extension/x.shell-extension.zip?version_tag=1"}'; exit 0; }; done
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
  assert_eq "$(grep -c 'gnome-extensions install --force' "$STUB_LOG")" "4" "4 missing extensions"
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

test_gnome_module_loads_desktop_settings() {
  stub_gnome_tools
  "$ROOT/install.sh" --only gnome >/dev/null 2>&1
  assert_contains "$STUB_LOG" "dconf load /"
  assert_contains "$SANDBOX/dconf-loaded" "screensaver=['<Control><Alt>l']"
  assert_contains "$SANDBOX/dconf-loaded" "[org/gnome/shell/extensions/dash-to-dock]"
  assert_not_contains "$SANDBOX/dconf-loaded" "DP-4"
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
