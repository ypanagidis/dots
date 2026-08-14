#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
NIX_FILE="${2:-./cursor.nix}"

if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version> [nix-file]"
  echo "Example: $0 2.3"
  exit 1
fi

DOWNLOAD_URL="https://api2.cursor.sh/updates/download/golden/linux-x64/cursor/${VERSION}"

# Verify it's a real version by checking the redirect
REDIRECT=$(curl -sI "$DOWNLOAD_URL" | grep -i "^location:" | tr -d '\r' | cut -d' ' -f2)
ACTUAL=$(echo "$REDIRECT" | grep -oP 'Cursor-\K[0-9.]+' | cut -d. -f1,2)

if [[ "$ACTUAL" != "$VERSION" ]]; then
  echo "Warning: $VERSION redirects to $ACTUAL - version may not exist"
  exit 1
fi

FULL_VERSION=$(echo "$REDIRECT" | grep -oP 'Cursor-\K[0-9.]+')
echo "Updating to Cursor $FULL_VERSION"

NEW_HASH=$(nix-prefetch-url "$DOWNLOAD_URL" 2>/dev/null)

sed -i "s|cursor/[0-9.]*\"|cursor/${VERSION}\"|" "$NIX_FILE"
sed -i "s|sha256 = \".*\"|sha256 = \"$NEW_HASH\"|" "$NIX_FILE"

echo "Done. Hash: $NEW_HASH"
