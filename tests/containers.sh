#!/usr/bin/env bash
# Installs the terminal group in fresh Ubuntu containers, as a regular user with
# sudo, and checks that its tools run. Needs Docker and an internet connection;
# each release takes a few minutes.
#   tests/containers.sh                # 24.04 25.10 26.04
#   tests/containers.sh 26.04          # one release
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RELEASES=("$@")
[[ ${#RELEASES[@]} -gt 0 ]] || RELEASES=(24.04 25.10 26.04)
TOOLS="fish nvim starship lazygit yazi btop rg fd gh claude opencode engram gentle-ai node ccstatusline codegraph"

# Runs inside the container as root: a sudo user, a copy of ducal, the install, the checks.
read -r -d '' SCRIPT <<'EOF'
set -e
apt-get update -qq >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sudo >/dev/null
useradd -m -s /bin/bash dev
echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev
cp -r /src /home/dev/ducal && chown -R dev: /home/dev/ducal
su - dev -c 'cd ducal && DUCAL_GROUPS=terminal DUCAL_EXTRAS=none ./install.sh </dev/null' 2>&1 |
  grep -E '==>|✓|!|✗' || true
su - dev -c 'export PATH=$HOME/.local/bin:$HOME/.local/share/fnm/aliases/default/bin:$PATH
  missing=""
  for t in '"$TOOLS"'; do command -v "$t" >/dev/null || missing="$missing $t"; done
  grep -q ccstatusline ~/.claude/settings.json || missing="$missing status-line"
  if [ -n "$missing" ]; then echo "MISSING:$missing"; exit 1; fi
  echo "ALL TOOLS FOUND"'
EOF

failed=0
for release in "${RELEASES[@]}"; do
  echo "=== ubuntu:$release"
  # $TOOLS in the script is filled in here: `su -` starts with a clean environment
  if docker run --rm -v "$ROOT:/src:ro" "ubuntu:$release" bash -c "${SCRIPT//\$TOOLS/$TOOLS}"; then
    echo "=== ubuntu:$release: ok"
  else
    echo "=== ubuntu:$release: FAILED"
    failed=1
  fi
done
exit $failed
