#!/usr/bin/env bash
# Copy packages/ into the client's ui-packages folder.
# Usage: ./install.sh [package-name ...]   (default: all packages)
# Set SPIRITECH_UI_PACKAGES to override the destination.
set -euo pipefail
cd "$(dirname "$0")/packages"
DEST="${SPIRITECH_UI_PACKAGES:-$HOME/.local/share/ProjectRubiKa/ui-packages}"
mkdir -p "$DEST"
if [ $# -gt 0 ]; then pkgs=("$@"); else pkgs=(spiritech.*/); fi
for p in "${pkgs[@]}"; do
  p="${p%/}"
  [ -f "$p/package.xml" ] || { echo "skip $p: no package.xml" >&2; continue; }
  # --delete only inside this package's folder; other addons are never touched.
  rsync -a --delete --exclude tools/ --exclude __pycache__/ "$p/" "$DEST/$p/"
  echo "installed $p"
done
if pgrep -f PRK.Client >/dev/null; then
  echo "note: the client is running; restart it or reload UI to pick up changes." >&2
fi
