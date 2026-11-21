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

test_theme_apply_colors_the_workspace_bar() {
  "$ROOT/bin/ducal" theme gruvbox >/dev/null 2>&1
  local p=/org/gnome/shell/extensions/space-bar/appearance
  assert_contains "$STUB_LOG" "dconf write $p/active-workspace-background-color '#7daea3'"
  assert_contains "$STUB_LOG" "dconf write $p/active-workspace-text-color '#282828'"
  assert_contains "$STUB_LOG" "dconf write $p/inactive-workspace-text-color '#d4be98'"
  assert_contains "$STUB_LOG" "dconf write $p/empty-workspace-text-color '#7c6f64'"
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
  assert_eq "$(grep -c 'gnome-extensions install --force' "$STUB_LOG")" "5" "5 missing extensions"
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
  # Numbered workspaces: Super+N goes there, Super+Shift+N sends the window
  assert_contains "$SANDBOX/dconf-loaded" "dynamic-workspaces=false"
  assert_contains "$SANDBOX/dconf-loaded" "switch-to-workspace-2=['<Super>2']"
  assert_contains "$SANDBOX/dconf-loaded" "move-to-workspace-4=['<Super><Shift>4']"
  assert_contains "$SANDBOX/dconf-loaded" "switch-to-application-1=@as []"
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

test_assets_module_installs_themes_icons_cursors_and_wallpapers() {
  stub_asset_tools
  "$ROOT/install.sh" --only assets >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$STUB_LOG" "Fausto-Korpsvart/Tokyonight-GTK-Theme"
  assert_contains "$STUB_LOG" "Fausto-Korpsvart/Gruvbox-GTK-Theme"
  assert_contains "$STUB_LOG" "upstream-install Tela-circle-icon-theme"
  assert_contains "$HOME/.icons/Vimix-white-cursors/index.theme" "cursor"
  assert_contains "$HOME/.icons/default/index.theme" "Inherits=Vimix-white-cursors"
  local w="$HOME/.local/share/ducal/wallpapers"
  [[ -s $w/omarchy-tokyo-liftoff.webp && -s $w/omarchy-gruvbox-backwater.jpg ]] || fail "wallpapers missing: $(ls "$w" 2>&1)"
  assert_eq "$(cat "$HOME/.config/ducal/current" 2>/dev/null)" "tokyo-night" "default theme applied"
}

test_assets_module_skips_what_is_already_installed() {
  stub_asset_tools
  mkdir -p "$HOME/.themes/Tokyonight-Dark" "$HOME/.themes/Gruvbox-Dark" "$HOME/.local/share/icons/Tela-circle-dark" \
    "$HOME/.icons/Vimix-white-cursors" "$HOME/.local/share/ducal/wallpapers" "$HOME/.config/ducal"
  # Non-empty: an empty file counts as an interrupted download and is fetched again
  echo img > "$HOME/.local/share/ducal/wallpapers/omarchy-tokyo-liftoff.webp"
  echo img > "$HOME/.local/share/ducal/wallpapers/omarchy-gruvbox-backwater.jpg"
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
  assert_contains "$r/etc/gdm3/greeter.dconf-defaults.ducal-logo-line" "#logo='/x.png'"
  assert_contains "$STUB_LOG" "dpkg-reconfigure gdm3"
  local p="$r/usr/share/plymouth/themes/ducal"
  assert_contains "$p/ducal.plymouth" "BackgroundStartColor=0x1a1b26"
  assert_contains "$p/ducal.plymouth" "ImageDir=/usr/share/plymouth/themes/ducal"
  [[ -s $p/watermark.png && -f $p/throbber-0001.png ]] || fail "plymouth images missing"
  assert_contains "$STUB_LOG" "update-alternatives --set default.plymouth $p/ducal.plymouth"
  assert_contains "$STUB_LOG" "update-initramfs -u"
}

test_system_install_without_logo_keeps_distro_logo() {
  setup_sysroot
  DUCAL_SYSTEM=yes "$ROOT/install.sh" --only system >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_not_contains "$DUCAL_SYSROOT/etc/gdm3/greeter.dconf-defaults" "ducal-logo"
  [[ ! -e $DUCAL_SYSROOT/usr/share/plymouth/themes/ducal/watermark.png ]] || fail "no watermark expected"
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

test_system_reinstall_without_logo_removes_the_logo() {
  setup_sysroot
  DUCAL_SYSTEM=yes DUCAL_LOGO="$SANDBOX/logo.svg" "$ROOT/install.sh" --only system >/dev/null 2>&1
  DUCAL_SYSTEM=yes "$ROOT/install.sh" --only system >/dev/null 2>&1
  assert_not_contains "$DUCAL_SYSROOT/etc/gdm3/greeter.dconf-defaults" "ducal-logo"
  assert_contains "$DUCAL_SYSROOT/etc/gdm3/greeter.dconf-defaults" "#logo='/x.png'"
  [[ ! -e $DUCAL_SYSROOT/usr/share/pixmaps/ducal-logo.svg ]] || fail "logo file left behind"
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
  printf 'rhythmbox\ngedit\n' > "$SANDBOX/installed"
  DUCAL_CLEANUP=apps "$ROOT/install.sh" --only cleanup >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  assert_contains "$STUB_LOG" "apt-get remove -y rhythmbox gedit"
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
  printf 'ubuntu-report\napport\nwhoopsie\nkerneloops\n' > "$SANDBOX/installed"
  DUCAL_CLEANUP=telemetry "$ROOT/install.sh" --only cleanup >/dev/null 2>&1
  assert_contains "$STUB_LOG" "apt-get remove -y ubuntu-report apport whoopsie kerneloops"
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
  mkdir -p "$HOME/.local/share/ducal/wallpapers"; echo img > "$HOME/.local/share/ducal/wallpapers/omarchy-gruvbox-backwater.jpg"
  "$ROOT/bin/ducal" wallpaper "$SANDBOX/mine.png" >/dev/null 2>&1
  : > "$STUB_LOG"
  "$ROOT/bin/ducal" theme gruvbox >/dev/null 2>&1
  assert_contains "$STUB_LOG" "picture-uri-dark file://$HOME/.config/ducal/wallpaper.png"
  assert_not_contains "$STUB_LOG" "backwater"
}

test_wallpaper_reset_returns_to_the_theme_wallpaper() {
  make_png "$SANDBOX/mine.png"
  mkdir -p "$HOME/.local/share/ducal/wallpapers"; echo img > "$HOME/.local/share/ducal/wallpapers/omarchy-gruvbox-backwater.jpg"
  "$ROOT/bin/ducal" theme gruvbox >/dev/null 2>&1
  "$ROOT/bin/ducal" wallpaper "$SANDBOX/mine.png" >/dev/null 2>&1
  : > "$STUB_LOG"
  "$ROOT/bin/ducal" wallpaper reset >/dev/null 2>&1; local rc=$?
  assert_eq "$rc" "0"
  [[ ! -e $HOME/.config/ducal/wallpaper.png ]] || fail "custom wallpaper should be removed"
  assert_contains "$STUB_LOG" "picture-uri-dark file://$HOME/.local/share/ducal/wallpapers/omarchy-gruvbox-backwater.jpg"
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
  printf '#!/usr/bin/env bash\n[[ -f "%s/typed" ]] || exit 1\ncat "%s/typed"\n' "$SANDBOX" "$SANDBOX" > "$s/zenity"
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
