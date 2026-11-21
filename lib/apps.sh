#!/usr/bin/env bash
# Application installers for ducal. Source after lib/common.sh.
# Every installer is idempotent: it returns early when the app is already present.

DUCAL_EXTRAS_AVAILABLE=(chrome code docker go rust node steam discord)
DUCAL_FONT_DIR="$HOME/.local/share/fonts/JetBrainsMonoNerd"

# ---------------------------------------------------------------- helpers

is_pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }

# apt_install PKG... — installs only the packages that are missing.
apt_install() {
  local missing=() p
  for p in "$@"; do is_pkg_installed "$p" || missing+=("$p"); done
  [[ ${#missing[@]} -eq 0 ]] && return 0
  log_step "apt: installing ${missing[*]}"
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

# github_asset_url OWNER/REPO REGEX — download URL of the latest release asset matching REGEX.
github_asset_url() {
  local url
  url=$(curl -fsSL "https://api.github.com/repos/$1/releases/latest" |
    grep -oE '"browser_download_url": *"[^"]+"' | cut -d'"' -f4 | grep -E "$2" | head -1)
  [[ -n $url ]] || die "No release asset matching '$2' in $1"
  echo "$url"
}

# download URL DEST
download() { curl -fsSL --retry 3 -o "$2" "$1" || die "Download failed: $1"; }

# install_deb_url NAME URL — downloads a .deb and installs it with its dependencies.
install_deb_url() {
  local tmp
  tmp=$(mktemp -d)
  log_step "Installing $1"
  download "$2" "$tmp/$1.deb"
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp/$1.deb"
  rm -rf "$tmp"
}

require_x86_64() {
  [[ $(uname -m) == x86_64 ]] || die "ducal currently supports x86_64 only (found $(uname -m))"
}

# ---------------------------------------------------------------- base apps

install_kitty() {
  has_cmd kitty && return 0
  log_step "Installing kitty"
  curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
  ln -sf "$HOME/.local/kitty.app/bin/kitty" "$HOME/.local/kitty.app/bin/kitten" "$HOME/.local/bin/"
  cp "$HOME/.local/kitty.app/share/applications/kitty.desktop" "$HOME/.local/share/applications/"
  sed -i "s|Icon=kitty|Icon=$HOME/.local/kitty.app/share/icons/hicolor/256x256/apps/kitty.png|; s|Exec=kitty|Exec=$HOME/.local/kitty.app/bin/kitty|" \
    "$HOME/.local/share/applications/kitty.desktop"
}

install_neovim() {
  has_cmd nvim && return 0
  require_x86_64
  local tmp; tmp=$(mktemp -d)
  log_step "Installing Neovim"
  download "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz" "$tmp/nvim.tar.gz"
  rm -rf "$HOME/.local/nvim" && mkdir -p "$HOME/.local/nvim" "$HOME/.local/bin"
  tar -xzf "$tmp/nvim.tar.gz" -C "$HOME/.local/nvim" --strip-components=1
  ln -sf "$HOME/.local/nvim/bin/nvim" "$HOME/.local/bin/nvim"
  rm -rf "$tmp"
}

install_starship() {
  has_cmd starship && return 0
  require_x86_64
  local tmp; tmp=$(mktemp -d)
  log_step "Installing Starship"
  download "https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-musl.tar.gz" "$tmp/s.tar.gz"
  mkdir -p "$HOME/.local/bin" && tar -xzf "$tmp/s.tar.gz" -C "$HOME/.local/bin" starship
  rm -rf "$tmp"
}

install_lazygit() {
  has_cmd lazygit && return 0
  require_x86_64
  local tmp; tmp=$(mktemp -d)
  log_step "Installing lazygit"
  download "$(github_asset_url jesseduffield/lazygit '_linux_x86_64\.tar\.gz$')" "$tmp/lg.tar.gz"
  mkdir -p "$HOME/.local/bin" && tar -xzf "$tmp/lg.tar.gz" -C "$HOME/.local/bin" lazygit
  rm -rf "$tmp"
}

install_yazi() {
  if ! has_cmd yazi; then
    require_x86_64
    log_step "Installing yazi"
    install_deb_url yazi "$(github_asset_url sxyazi/yazi 'x86_64-unknown-linux-gnu\.deb$')"
  fi
  # Color flavors used by `ducal theme`
  local flavors="$HOME/.config/yazi/flavors"
  [[ -d $flavors/tokyo-night.yazi ]] || ya pkg add BennyOe/tokyo-night || log_warn "Could not add the tokyo-night yazi flavor"
  [[ -d $flavors/gruvbox-dark.yazi ]] || ya pkg add bennyyip/gruvbox-dark || log_warn "Could not add the gruvbox-dark yazi flavor"
}

install_claude() {
  has_cmd claude && return 0
  log_step "Installing Claude Code CLI"
  # Official native installer: puts the binary in ~/.local/bin and keeps it updated
  curl -fsSL https://claude.ai/install.sh | bash
}

install_nerd_font() {
  [[ -d $DUCAL_FONT_DIR ]] && return 0
  local tmp; tmp=$(mktemp -d)
  log_step "Installing JetBrainsMono Nerd Font"
  download "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" "$tmp/font.zip"
  mkdir -p "$DUCAL_FONT_DIR" && unzip -oq "$tmp/font.zip" '*.ttf' -d "$DUCAL_FONT_DIR"
  fc-cache -f >/dev/null
  rm -rf "$tmp"
}

install_base() {
  apt_install git curl unzip fontconfig build-essential fish btop ripgrep fd-find gh
  # Ubuntu ships fd as fdfind; tools like LazyVim look for `fd`
  if ! has_cmd fd && has_cmd fdfind; then
    mkdir -p "$HOME/.local/bin" && ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
  fi
  install_kitty
  install_neovim
  install_starship
  install_lazygit
  install_yazi
  install_claude
  install_nerd_font
}

# ---------------------------------------------------------------- extras

install_extra_chrome() {
  has_cmd google-chrome && return 0
  install_deb_url google-chrome "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
}

install_extra_code() {
  has_cmd code && return 0
  install_deb_url code "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
}

install_extra_docker() {
  if ! has_cmd docker; then
    log_step "Installing Docker Engine"
    apt_install ca-certificates curl
    as_root install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | as_root tee /etc/apt/keyrings/docker.asc >/dev/null
    as_root chmod a+r /etc/apt/keyrings/docker.asc
    # shellcheck source=/dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
      as_root tee /etc/apt/sources.list.d/docker.list >/dev/null
    as_root apt-get update
    apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi
  if ! id -nG "$USER" | grep -qw docker; then
    log_warn "Adding $USER to the docker group: this grants root-equivalent access to Docker. Log out to apply."
    as_root usermod -aG docker "$USER"
  fi
}

install_extra_go() {
  [[ -x /usr/local/go/bin/go ]] && return 0
  require_x86_64
  local version tmp
  version=$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1)
  tmp=$(mktemp -d)
  log_step "Installing $version"
  download "https://go.dev/dl/$version.linux-amd64.tar.gz" "$tmp/go.tar.gz"
  as_root rm -rf /usr/local/go
  as_root tar -C /usr/local -xzf "$tmp/go.tar.gz"
  rm -rf "$tmp"
}

install_extra_rust() {
  has_cmd rustup && return 0
  log_step "Installing Rust (rustup)"
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path
}

install_extra_node() {
  local fnm_dir="$HOME/.local/share/fnm"
  if [[ ! -x $fnm_dir/fnm ]]; then
    log_step "Installing fnm"
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "$fnm_dir" --skip-shell
  fi
  if [[ ! -d $fnm_dir/aliases/default ]]; then
    log_step "Installing Node.js LTS"
    FNM_DIR="$fnm_dir" "$fnm_dir/fnm" install --lts
    FNM_DIR="$fnm_dir" "$fnm_dir/fnm" default lts-latest
  fi
  # Shells only read their rc files when interactive; editors, MCP servers and
  # AI agents start non-interactive processes, so Node goes in the session environment.
  mkdir -p "$HOME/.config/environment.d"
  printf '%s\n' '# Managed by ducal: Node.js (fnm default) for every program in the session' \
    'PATH=${HOME}/.local/share/fnm/aliases/default/bin:${PATH}' > "$HOME/.config/environment.d/60-ducal-node.conf"
  install_ccstatusline "$fnm_dir/aliases/default/bin"
}

# Status line for Claude Code; the config module wires it up (pinned: its config format is versioned)
install_ccstatusline() {
  local bin=$1
  [[ -x $bin/ccstatusline ]] && return 0
  if [[ ! -x $bin/npm ]]; then
    log_warn "npm not found; skipping the Claude Code status line"
    return 0
  fi
  log_step "Installing ccstatusline"
  PATH="$bin:$PATH" "$bin/npm" install -g ccstatusline@2.2.34
}

install_extra_steam() {
  has_cmd steam && return 0
  as_root dpkg --add-architecture i386
  install_deb_url steam "https://cdn.akamai.steamstatic.com/client/installer/steam.deb"
}

install_extra_discord() {
  has_cmd discord && return 0
  install_deb_url discord "https://discord.com/api/download?platform=linux&format=deb"
}

# parse_extras "chrome, code" | all | none -> space-separated validated names
parse_extras() {
  local input=${1// /} name out=()
  case $input in
    all) echo "${DUCAL_EXTRAS_AVAILABLE[*]}"; return 0 ;;
    none | "") echo ""; return 0 ;;
  esac
  IFS=',' read -ra names <<<"$input"
  for name in "${names[@]}"; do
    [[ " ${DUCAL_EXTRAS_AVAILABLE[*]} " == *" $name "* ]] || die "Unknown extra: $name (available: ${DUCAL_EXTRAS_AVAILABLE[*]})"
    out+=("$name")
  done
  echo "${out[*]}"
}

# select_extras — from $DUCAL_EXTRAS, else ask on a terminal, else none.
select_extras() {
  if [[ -n ${DUCAL_EXTRAS:-} ]]; then parse_extras "$DUCAL_EXTRAS"; return; fi
  if [[ ! -t 0 ]]; then echo ""; return; fi
  local chosen=() name answer
  for name in "${DUCAL_EXTRAS_AVAILABLE[@]}"; do
    read -r -p "Install $name? [y/N] " answer </dev/tty
    [[ ${answer,,} == y ]] && chosen+=("$name")
  done
  echo "${chosen[*]}"
}
