#!/usr/bin/env bash
# Download one release asset and verify it before anything uses it.
#
# Usage: scripts/fetch-verified.sh <checksums-url> <checksums-sha256> <asset-url> <out-file>
#
# Two-step trust: the release's checksums file must match the sha256 pinned in
# the Makefile (so a re-uploaded release is caught), and the asset must match
# its line in that checksums file. One pin per tool version covers every
# platform's asset. Accepts "<hash>  name" and "<hash> *./dir/name" lines.
set -euo pipefail

checksums_url=${1:?checksums-url}
checksums_sha256=${2:?checksums-sha256}
asset_url=${3:?asset-url}
out=${4:?out-file}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL --proto '=https' -o "$tmp/checksums" "$checksums_url"
echo "$checksums_sha256  $tmp/checksums" | sha256sum -c --quiet - || {
  echo "fetch-verified: $checksums_url does not match the sha256 pinned in the Makefile" >&2
  exit 1
}

name=${asset_url##*/}
expected=$(awk -v n="$name" '{ f = $2; sub(/^\*/, "", f); sub(/.*\//, "", f); if (f == n) print $1 }' "$tmp/checksums")
if [ -z "$expected" ]; then
  echo "fetch-verified: no checksum for $name in $checksums_url" >&2
  exit 1
fi

curl -fsSL --proto '=https' -o "$tmp/$name" "$asset_url"
echo "$expected  $tmp/$name" | sha256sum -c --quiet - || {
  echo "fetch-verified: $name does not match its published checksum" >&2
  exit 1
}

mkdir -p "$(dirname "$out")"
mv "$tmp/$name" "$out"
