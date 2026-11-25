#!/usr/bin/env bash
# ducal in one line:
#   curl -fsSL https://raw.githubusercontent.com/yusney/ducal/main/boot.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/yusney/ducal/main/boot.sh | bash -s -- --profile dev
# Clones ducal into ~/.local/share/ducal (or updates it), then runs ./install.sh
# with the given arguments. DUCAL_DIR and DUCAL_REPO change where from and where to.
set -euo pipefail

# download_into REPO DIR — the repository's default branch checked out in DIR,
# which already holds other files. Git refuses to overwrite any of them.
download_into() {
  local repo=$1 dir=$2 branch
  branch=$(git ls-remote --symref "$repo" HEAD | sed -n 's|^ref: refs/heads/\(.*\)[[:space:]]HEAD$|\1|p')
  [[ -n $branch ]] || return 1
  git -C "$dir" init --quiet &&
    git -C "$dir" remote add origin "$repo" &&
    git -C "$dir" fetch --quiet origin "$branch" &&
    git -C "$dir" checkout --quiet -b "$branch" --track "origin/$branch"
}

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
  elif [[ -d $dir && -n $(ls -A "$dir") ]]; then
    # ducal keeps its wallpapers and downloads here too: a desktop installed from
    # another copy has them without the repository. Download around them.
    echo "==> Downloading ducal into $dir (keeping the files already there)"
    if ! download_into "$repo" "$dir"; then
      rm -rf "$dir/.git"
      echo "Could not download ducal into $dir: move away the files in the way, or set DUCAL_DIR to another folder" >&2
      exit 1
    fi
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
