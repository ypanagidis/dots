#!/usr/bin/env bash
set -euo pipefail

VERSION_INPUT="${1:-}"
NIX_FILE="${2:-./default.nix}"

if [[ ! -f "$NIX_FILE" ]]; then
  echo "Nix file not found: $NIX_FILE"
  exit 1
fi

if [[ -n "$VERSION_INPUT" ]]; then
  VERSION="${VERSION_INPUT#v}"
  TAG="v${VERSION}"
  RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/pingdotgg/t3code/releases/tags/${TAG}")
else
  RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/pingdotgg/t3code/releases?per_page=20")
  TAG=$(printf '%s' "$RELEASE_JSON" | jq -r '[.[] | select(any(.assets[]?; .name | endswith("x86_64.AppImage")))][0].tag_name // empty')

  if [[ -z "$TAG" ]]; then
    echo "Could not find a release with an x86_64.AppImage asset"
    exit 1
  fi

  RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/pingdotgg/t3code/releases/tags/${TAG}")
  VERSION="${TAG#v}"
fi

ASSET_DIGEST=$(printf '%s' "$RELEASE_JSON" | jq -r '[.assets[] | select(.name | endswith("x86_64.AppImage"))][0].digest // empty')

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

echo "Updated T3 Code to ${VERSION}"
echo "Hash: ${NEW_HASH}"
