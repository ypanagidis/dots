#!/usr/bin/env bash
set -euo pipefail

VERSION_INPUT="${1:-}"
NIX_FILE="${2:-./helium.nix}"

if [[ ! -f "$NIX_FILE" ]]; then
  echo "Nix file not found: $NIX_FILE"
  exit 1
fi

if [[ -n "$VERSION_INPUT" ]]; then
  VERSION="${VERSION_INPUT#v}"
  TAG="${VERSION}"
  RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/imputnet/helium-linux/releases/tags/${TAG}")
else
  RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/imputnet/helium-linux/releases/latest")
  TAG=$(printf '%s' "$RELEASE_JSON" | jq -r '.tag_name // empty')
  VERSION="$TAG"
fi

ASSET_DIGEST=$(printf '%s' "$RELEASE_JSON" | jq -r '[.assets[] | select(.name | endswith("-x86_64.AppImage"))][0].digest // empty')

if [[ -z "$ASSET_DIGEST" || "$ASSET_DIGEST" == "null" ]]; then
  echo "Could not find digest for x86_64.AppImage asset in ${TAG}"
  exit 1
fi

DIGEST_HEX="${ASSET_DIGEST#sha256:}"
NEW_HASH=$(nix hash convert --hash-algo sha256 --to sri "$DIGEST_HEX")

CURRENT_VERSION=$(grep -oP 'version = "\K[^"]+' "$NIX_FILE" | head -n1)
CURRENT_HASH=$(grep -oP 'hash = "\K[^"]+' "$NIX_FILE" | head -n1)

if [[ "$CURRENT_VERSION" == "$VERSION" && "$CURRENT_HASH" == "$NEW_HASH" ]]; then
  echo "Already up to date: ${VERSION}"
  exit 0
fi

sed -i "s|version = \".*\";|version = \"${VERSION}\";|" "$NIX_FILE"
sed -i "s|hash = \"sha256-[^\"]*\";|hash = \"${NEW_HASH}\";|" "$NIX_FILE"

echo "Updated Helium to ${VERSION}"
echo "Hash: ${NEW_HASH}"
