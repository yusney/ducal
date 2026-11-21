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

# ---------------------------------------------------------------- run
ORIG_PATH=$PATH
ORIG_HOME=$HOME
echo "ducal tests"
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do run_test "$t"; done
export HOME=$ORIG_HOME
echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
