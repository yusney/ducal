#!/usr/bin/env bash
# Application installers for ducal. Source after lib/common.sh.
# Every installer is idempotent: it returns early when the app is already present.

DUCAL_EXTRAS_AVAILABLE=(chrome code docker go rust node steam discord)
DUCAL_FONT_DIR="$HOME/.local/share/fonts/JetBrainsMonoNerd"

# ---------------------------------------------------------------- helpers

is_pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }

# LC_ALL=C: apt-cache translates "Candidate". The whole output is read first:
# `| grep -q` would stop early and, under pipefail, fail with SIGPIPE.
has_apt_candidate() {
  local policy
  policy=$(LC_ALL=C apt-cache policy "$1" 2>/dev/null) || return 1
  [[ $policy =~ Candidate:\ [^\(] ]]
}

# apt_install PKG... — installs only the packages that are missing. A package
# this release does not have (newer Ubuntu releases drop some) is skipped with
# a warning, after refreshing the package lists once in case they are old.
apt_install() {
  local missing=() available=() p
  for p in "$@"; do is_pkg_installed "$p" || missing+=("$p"); done
  [[ ${#missing[@]} -eq 0 ]] && return 0
  for p in "${missing[@]}"; do
    if ! has_apt_candidate "$p" && [[ -z ${DUCAL_APT_UPDATED:-} ]]; then
      as_root apt-get update -qq || log_warn "apt-get update failed"
      DUCAL_APT_UPDATED=1
    fi
    if has_apt_candidate "$p"; then
      available+=("$p")
    else
      log_warn "$p is not available on this release, skipping it"
    fi
  done
  missing=("${available[@]}")
  [[ ${#missing[@]} -eq 0 ]] && return 0
  log_step "apt: installing ${missing[*]}"
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
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
  local releases=https://github.com/jesseduffield/lazygit/releases release_url tag tmp
  log_step "Installing lazygit"
  # Resolve the version via the public release redirect, without the GitHub API.
  release_url=$(curl -fsSIL --retry 3 -o /dev/null -w '%{url_effective}' "$releases/latest") ||
    die "Could not resolve the latest Lazygit release: $releases/latest"
  tag=${release_url##*/}
  [[ $release_url == "$releases/tag/$tag" && $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    die "Unexpected Lazygit release URL: $release_url"
  tmp=$(mktemp -d)
  download "$releases/download/$tag/lazygit_${tag#v}_linux_x86_64.tar.gz" "$tmp/lg.tar.gz"
  mkdir -p "$HOME/.local/bin" && tar -xzf "$tmp/lg.tar.gz" -C "$HOME/.local/bin" lazygit
  rm -rf "$tmp"
}

install_yazi() {
  if ! has_cmd yazi; then
    require_x86_64
    local tmp; tmp=$(mktemp -d)
    log_step "Installing yazi"
    # The static musl build: the .deb needs glibc 2.39, newer than Ubuntu 22.04 has
    download "https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-musl.zip" "$tmp/yazi.zip"
    unzip -oq "$tmp/yazi.zip" -d "$tmp"
    mkdir -p "$HOME/.local/bin"
    install -m 755 "$tmp"/yazi-x86_64-unknown-linux-musl/{yazi,ya} "$HOME/.local/bin/"
    rm -rf "$tmp"
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

# install_gentleman_release NAME: latest Gentleman-Programming/NAME release binary
# into ~/.local/bin. Resolved via the public release redirect, without the GitHub API.
install_gentleman_release() {
  local name=$1 releases release_url tag tmp
  has_cmd "$name" && return 0
  require_x86_64
  releases="https://github.com/Gentleman-Programming/$name/releases"
  log_step "Installing $name"
  release_url=$(curl -fsSIL --retry 3 -o /dev/null -w '%{url_effective}' "$releases/latest") ||
    { log_warn "Could not resolve the latest $name release: $releases/latest"; return 0; }
  tag=${release_url##*/}
  if [[ $release_url != "$releases/tag/$tag" || ! $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_warn "Unexpected $name release URL: $release_url"
    return 0
  fi
  tmp=$(mktemp -d)
  if curl -fsSL --retry 3 -o "$tmp/$name.tar.gz" "$releases/download/$tag/${name}_${tag#v}_linux_amd64.tar.gz"; then
    mkdir -p "$HOME/.local/bin" && tar -xzf "$tmp/$name.tar.gz" -C "$HOME/.local/bin" "$name"
  else
    log_warn "Could not download $name $tag"
  fi
  rm -rf "$tmp"
}

# Claude Code plugins ducal installs: "plugin@marketplace github-repo"
DUCAL_CLAUDE_PLUGINS=(
  "engram@engram Gentleman-Programming/engram"
  "warp@claude-code-warp warpdotdev/claude-code-warp"
)

# add_claude_mcp NAME ARGS...: user-scoped MCP server, skipped when it already exists
add_claude_mcp() {
  local name=$1; shift
  claude mcp get "$name" >/dev/null 2>&1 && return 0
  claude mcp add -s user "$name" "$@" >/dev/null || log_warn "Could not add the $name MCP server to Claude Code"
}

# Claude Code extras: Node (status line, codegraph, context7), engram, gentle-ai,
# plugins and MCP servers. Each step is skipped when already in place; a failure
# only warns, so the rest of the install goes on.
setup_claude_code() {
  if ! has_cmd claude; then
    log_warn "Claude Code CLI not found; skipping its plugins and MCP servers"
    return 0
  fi
  install_extra_node
  local node_bin="$HOME/.local/share/fnm/aliases/default/bin" entry plugin repo engram_bin
  PATH="$node_bin:$PATH"
  install_gentleman_release engram
  install_gentleman_release gentle-ai
  if ! has_cmd codegraph; then
    log_step "Installing codegraph"
    npm install -g @colbymchenry/codegraph@1.6.3 || log_warn "Could not install codegraph"
  fi
  for entry in "${DUCAL_CLAUDE_PLUGINS[@]}"; do
    read -r plugin repo <<<"$entry"
    claude plugin list 2>/dev/null | grep -qF "$plugin" && continue
    log_step "Installing the Claude Code plugin $plugin"
    { claude plugin marketplace add "$repo" && claude plugin install -s user "$plugin"; } >/dev/null ||
      log_warn "Could not install the Claude Code plugin $plugin"
  done
  engram_bin=$(command -v engram || echo "$HOME/.local/bin/engram")
  add_claude_mcp codegraph -- codegraph serve --mcp
  add_claude_mcp context7 -- npx -y --package=@upstash/context7-mcp@2.2.5 -- context7-mcp
  add_claude_mcp engram -- "$engram_bin" mcp --tools=agent
  # Stitch needs a personal Google API key: STITCH_API_KEY, or a placeholder to
  # replace later in ~/.claude.json. An existing stitch server is kept as it is.
  add_claude_mcp stitch --transport http https://stitch.googleapis.com/mcp \
    --header "X-Goog-Api-Key: ${STITCH_API_KEY:-YOUR_STITCH_API_KEY}"
  log_ok "Claude Code plugins and MCP servers ready"
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

install_opencode() {
  has_cmd opencode && return 0
  log_step "Installing opencode"
  # Official installer; --no-modify-path keeps it out of the shell files ducal links
  curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path
  mkdir -p "$HOME/.local/bin" && ln -sf "$HOME/.opencode/bin/opencode" "$HOME/.local/bin/opencode"
}

# Group terminal: command-line tools, they work without a graphical session (WSL too)
install_terminal_tools() {
  apt_install git curl unzip build-essential fish btop ripgrep fd-find gh
  # Ubuntu ships fd as fdfind; tools like LazyVim look for `fd`
  if ! has_cmd fd && has_cmd fdfind; then
    mkdir -p "$HOME/.local/bin" && ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
  fi
  install_neovim
  install_starship
  install_lazygit
  install_yazi
  install_claude
  install_opencode
  setup_claude_code
}

# Group desktop-apps: the graphical terminal and its font
install_desktop_apps() {
  apt_install curl unzip fontconfig
  install_kitty
  install_nerd_font
}

install_base() {
  install_terminal_tools
  install_desktop_apps
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

# docker_repo_codename — this release's codename, or noble (24.04) while Docker
# has not published packages for it yet (new releases wait a few months).
docker_repo_codename() {
  local codename
  codename=$(sed -n 's/^VERSION_CODENAME=//p' "${DUCAL_SYSROOT:-}/etc/os-release" | tr -d '"')
  if [[ -n $codename ]] && curl -fsSL --retry 2 -o /dev/null "https://download.docker.com/linux/ubuntu/dists/$codename/Release"; then
    echo "$codename"
  else
    log_warn "Docker has no packages for Ubuntu ${codename:-this release} yet, using the 24.04 (noble) ones"
    echo noble
  fi
}

install_extra_docker() {
  if ! has_cmd docker; then
    log_step "Installing Docker Engine"
    apt_install ca-certificates curl
    as_root install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | as_root tee /etc/apt/keyrings/docker.asc >/dev/null
    as_root chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(docker_repo_codename) stable" |
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
