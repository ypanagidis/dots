#!/usr/bin/env bash
# Bump the Wispr Flow AppImage pin in flake.nix to the latest stable
# wispr-flow-linux release (tags look like v1.0.4+wispr1.6.957).
set -euo pipefail

REPO="wispr-flow-linux/wispr-flow-linux"
NIX_FILE="$(dirname "$0")/flake.nix"

RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest")
TAG=$(jq -r '.tag_name' <<<"$RELEASE_JSON")

if [[ ! "$TAG" =~ ^v([0-9.]+)\+wispr([0-9.]+)$ ]]; then
  echo "Unexpected release tag: ${TAG}"
  exit 1
fi
PORT_VERSION="${BASH_REMATCH[1]}"
APP_VERSION="${BASH_REMATCH[2]}"
ASSET="wispr-flow-${APP_VERSION}-${PORT_VERSION}-x86_64.AppImage"

DIGEST=$(jq -r --arg a "$ASSET" '.assets[] | select(.name == $a) | .digest // empty' <<<"$RELEASE_JSON")
if [[ -z "$DIGEST" ]]; then
  echo "No digest for ${ASSET} in ${TAG}"
  exit 1
fi
NEW_HASH=$(nix hash convert --hash-algo sha256 --to sri "${DIGEST#sha256:}")

CURRENT_APP=$(grep -oP 'wisprAppVersion = "\K[^"]+' "$NIX_FILE")
CURRENT_PORT=$(grep -oP 'wisprPortVersion = "\K[^"]+' "$NIX_FILE")
if [[ "$CURRENT_APP" == "$APP_VERSION" && "$CURRENT_PORT" == "$PORT_VERSION" ]]; then
  echo "Already up to date: ${APP_VERSION}-${PORT_VERSION}"
  exit 1
fi

sed -i \
  -e "s|wisprAppVersion = \"[^\"]*\";|wisprAppVersion = \"${APP_VERSION}\";|" \
  -e "s|wisprPortVersion = \"[^\"]*\";|wisprPortVersion = \"${PORT_VERSION}\";|" \
  "$NIX_FILE"
# The Wispr AppImage hash is the only sha256- hash in the file.
sed -i "/wisprFlowSrc = /,/};/ s|hash = \"sha256-[^\"]*\";|hash = \"${NEW_HASH}\";|" "$NIX_FILE"

echo "Updated Wispr Flow ${CURRENT_APP}-${CURRENT_PORT} -> ${APP_VERSION}-${PORT_VERSION}"
