#!/usr/bin/env bash
# Build dist/modern-ui-<version>.zip for upload.
#
# Spiritech publishing rules:
#   - each package in its own top-level folder with a package.xml (nothing else at the top level)
#   - every manifest carries the same version="" and the targeted apiVersion=""
#   - all required libraries are bundled
#   - published versions cannot be replaced
#
# Stamps version/apiVersion into every packages/*/package.xml, validates, then zips.
# tools/ folders are left out; LICENSE is copied into every package folder.
# Usage: ./release.sh 1.1.0            (API_VERSION=0.1.0 ./release.sh ... to override)
set -euo pipefail
cd "$(dirname "$0")"

version="${1:?usage: ./release.sh VERSION}"
api_version="${API_VERSION:-0.1.0}"
semver='^[0-9]+\.[0-9]+\.[0-9]+$'
[[ $version =~ $semver ]] || { echo "version must be MAJOR.MINOR.PATCH" >&2; exit 1; }
[[ $api_version =~ $semver ]] || { echo "API_VERSION must be MAJOR.MINOR.PATCH" >&2; exit 1; }

if git rev-parse -q --verify "refs/tags/v$version" >/dev/null \
   || git ls-remote --exit-code --tags origin "v$version" >/dev/null 2>&1; then
  echo "v$version is already tagged; published versions cannot be replaced" >&2
  exit 1
fi

# Stamp version + apiVersion on the <Package> element of every manifest, after id/name.
for manifest in packages/*/package.xml; do
  sed -E -i \
    -e '/<Package /{s/ (version|apiVersion)="[^"]*"//g; s/(<Package [^>]*)(\/?>)/\1 version="'"$version"'" apiVersion="'"$api_version"'"\2/}' \
    "$manifest"
done

# Validate.
fail=0
ids=()
for dir in packages/*/; do
  manifest="${dir}package.xml"
  [[ -f $manifest ]] || { echo "missing $manifest" >&2; fail=1; continue; }
  id=$(grep -oP '<Package [^>]*\bid="\K[^"]+' "$manifest")
  [[ "$(basename "$dir")" == "$id" ]] || { echo "$dir: folder name != id $id" >&2; fail=1; }
  grep -q "<Package [^>]*version=\"$version\"" "$manifest" || { echo "$manifest: version not $version" >&2; fail=1; }
  grep -q "<Package [^>]*apiVersion=\"$api_version\"" "$manifest" || { echo "$manifest: apiVersion not $api_version" >&2; fail=1; }
  ids+=("$id")
done
for req in $(grep -ohP 'Requires package="\K[^"]+' packages/*/package.xml | sort -u); do
  printf '%s\n' "${ids[@]}" | grep -qx "$req" || { echo "required package $req is not bundled" >&2; fail=1; }
done
(( fail == 0 )) || exit 1

# Build the zip from a staging copy so LICENSE sits inside each package folder.
out="$PWD/dist/modern-ui-$version.zip"
[[ -e $out ]] && { echo "$out already exists" >&2; exit 1; }
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
rsync -a --exclude 'tools/' --exclude '__pycache__/' packages/ "$stage/"
for dir in "$stage"/*/; do cp LICENSE "$dir"; done
mkdir -p dist
(cd "$stage" && zip -qr "$out" -- *)
echo "$out"
