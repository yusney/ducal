#!/usr/bin/env bash
# ducal in one line:
#   curl -fsSL https://raw.githubusercontent.com/yusney/ducal/main/boot.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/yusney/ducal/main/boot.sh | bash -s -- --profile dev
# Clones ducal into ~/.local/share/ducal (or updates it), then runs ./install.sh
# with the given arguments. DUCAL_DIR and DUCAL_REPO change where from and where to.
set -euo pipefail

# Everything runs from main, called on the last line: a download cut halfway runs nothing.
main() {
  local dir=${DUCAL_DIR:-$HOME/.local/share/ducal}
  local repo=${DUCAL_REPO:-https://github.com/yusney/ducal.git}

  if ! command -v git >/dev/null 2>&1; then
    echo "==> Installing git"
    sudo apt-get update -qq
    sudo apt-get install -y -qq git
  fi

  if [[ -d $dir/.git ]]; then
    echo "==> Updating ducal in $dir"
    git -C "$dir" pull --ff-only --quiet
  else
    echo "==> Downloading ducal into $dir"
    mkdir -p "$(dirname "$dir")"
    git clone --quiet "$repo" "$dir"
  fi

  cd "$dir"
  # With `curl | bash` the script itself is on stdin: give the installer the
  # terminal so its menus can ask. Without one, it runs with the defaults.
  if (exec </dev/tty) 2>/dev/null; then
    exec ./install.sh "$@" </dev/tty
  fi
  exec ./install.sh "$@"
}

main "$@"
