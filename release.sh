#!/usr/bin/env bash
# Build dist/modern-ui-<version>.zip: the spiritech.* package folders, ready to
# unzip into ~/.local/share/ProjectRubiKa/ui-packages/. tools/ folders are left out.
# Usage: ./release.sh 1.0.0
set -euo pipefail
cd "$(dirname "$0")"
version="${1:?usage: ./release.sh VERSION}"
out="$PWD/dist/modern-ui-$version.zip"
mkdir -p dist
rm -f "$out"
(cd packages && zip -qr "$out" spiritech.* -x '*/tools/*' '*/__pycache__/*')
zip -qj "$out" LICENSE
echo "$out"
