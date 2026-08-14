#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUSTOM_DIR="$ROOT/custom-packages"
CUSTOM_FLAKE="$CUSTOM_DIR/flake.nix"
OXC_TARGET="${OXC_TARGET:-x86_64-unknown-linux-musl}"
TSGO_DIST_TAG="${TSGO_DIST_TAG:-beta}"
TSGO_NATIVE_PACKAGE="${TSGO_NATIVE_PACKAGE:-native-preview-linux-x64}"

usage() {
  printf 'Usage: %s [all|opencode|helium|t3|oxc|tsgo ...]\n' "${0##*/}"
  printf '\nUpdates manually pinned packages that normal flake updates miss.\n'
  printf 'opencode updates the sst/opencode flake input.\n'
  printf 'tsgo follows @typescript/native-preview@%s; override with TSGO_DIST_TAG.\n' "$TSGO_DIST_TAG"
  printf 'tsgo installs @typescript/%s; override with TSGO_NATIVE_PACKAGE.\n' "$TSGO_NATIVE_PACKAGE"
  printf 'Cursor is intentionally not included.\n'
}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

replace() {
  local file="$1"
  local expr="$2"
  perl -0pi -e "$expr" "$file"
}

github() {
  curl -fsSL -H 'Accept: application/vnd.github+json' "$1"
}

hash_from_github_asset() {
  local release_json="$1"
  local asset_name="$2"
  local url="$3"
  local digest hex

  digest="$(printf '%s' "$release_json" | jq -r --arg name "$asset_name" '.assets[] | select(.name == $name) | .digest // empty' | head -n1)"

  if [[ "$digest" == sha256:* ]]; then
    hex="${digest#sha256:}"
    nix hash convert --hash-algo sha256 --to sri "$hex"
  else
    nix store prefetch-file --json "$url" | jq -r '.hash'
  fi
}

update_custom_lock() {
  local input="$1"

  (cd "$ROOT" && nix flake update "custom-packages/$input")
  (cd "$CUSTOM_DIR" && nix flake update "$input")
}

update_opencode() {
  printf '\n==> Updating opencode\n'
  update_custom_lock opencode-flake
}

update_helium() {
  printf '\n==> Updating Helium\n'
  "$ROOT/modules/browsers/helium/update-helium.sh" "" "$ROOT/modules/browsers/helium/helium.nix"
}

update_t3() {
  printf '\n==> Updating T3 Code\n'
  "$ROOT/modules/ides/t3/update-t3.sh" "" "$ROOT/modules/ides/t3/default.nix"
}

update_oxc() {
  local releases tag version release_json app asset url hash

  printf '\n==> Updating Oxc apps\n'
  releases="$(github 'https://api.github.com/repos/oxc-project/oxc/releases?per_page=20')"
  tag="$(printf '%s' "$releases" | jq -r '[.[] | select(.tag_name | startswith("apps_v"))][0].tag_name // empty')"

  if [[ -z "$tag" ]]; then
    printf 'Could not find latest Oxc apps_v* release\n' >&2
    exit 1
  fi

  version="${tag#apps_v}"
  release_json="$(github "https://api.github.com/repos/oxc-project/oxc/releases/tags/$tag")"

  replace "$CUSTOM_FLAKE" "s#oxcAppsVersion = \"[^\"]+\";#oxcAppsVersion = \"$version\";#"

  for app in oxfmt oxlint; do
    asset="$app-$OXC_TARGET.tar.gz"
    url="https://github.com/oxc-project/oxc/releases/download/$tag/$asset"
    hash="$(hash_from_github_asset "$release_json" "$asset" "$url")"

    replace "$CUSTOM_FLAKE" "s#$app = \"sha256-[^\"]+\";#$app = \"$hash\";#"
    replace "$CUSTOM_FLAKE" "s#$app = oxcBinary \"$app\" \"[^\"]+\";#$app = oxcBinary \"$app\" \"$version\";#"

    printf 'Updated %s to %s (%s)\n' "$app" "$version" "$hash"
  done
}

update_tsgo() {
  local npm_json package_json native_json native_package_json rev version hash

  printf '\n==> Updating TypeScript Go / tsgo (%s)\n' "$TSGO_DIST_TAG"
  npm_json="$(curl -fsSL 'https://registry.npmjs.org/@typescript/native-preview')"
  version="$(printf '%s' "$npm_json" | jq -r --arg tag "$TSGO_DIST_TAG" '."dist-tags"[$tag] // empty')"
  package_json="$(printf '%s' "$npm_json" | jq -c --arg version "$version" '.versions[$version] // empty')"
  rev="$(printf '%s' "$package_json" | jq -r '.gitHead // empty')"

  if [[ -z "$version" ]]; then
    printf 'Could not resolve @typescript/native-preview@%s version\n' "$TSGO_DIST_TAG" >&2
    exit 1
  fi

  native_json="$(curl -fsSL "https://registry.npmjs.org/@typescript/$TSGO_NATIVE_PACKAGE")"
  native_package_json="$(printf '%s' "$native_json" | jq -c --arg version "$version" '.versions[$version] // empty')"
  hash="$(printf '%s' "$native_package_json" | jq -r '.dist.integrity // empty')"

  if [[ -z "$hash" ]]; then
    printf 'Could not resolve @typescript/%s@%s integrity hash\n' "$TSGO_NATIVE_PACKAGE" "$version" >&2
    exit 1
  fi

  replace "$CUSTOM_FLAKE" "s#(tsgoBinaryHashes = \\\{\\n[[:space:]]+x86_64-linux = \\\{\\n[[:space:]]+hash = \")[^\"]+(\";)#\${1}$hash\${2}#"
  replace "$CUSTOM_FLAKE" "s#(tsgoBinaryHashes = \\\{\\n[[:space:]]+x86_64-linux = \\\{\\n[[:space:]]+hash = \"[^\"]+\";\\n[[:space:]]+package = \")[^\"]+(\";)#\${1}$TSGO_NATIVE_PACKAGE\${2}#"
  replace "$CUSTOM_FLAKE" "s#tsgo = tsgoBinary \"[^\"]+\";#tsgo = tsgoBinary \"$version\";#"

  printf 'Updated tsgo to %s\n' "$version"
  [[ -n "$rev" ]] && printf 'gitHead: %s\n' "$rev"
  printf 'binary: @typescript/%s\n' "$TSGO_NATIVE_PACKAGE"
  printf 'hash: %s\n' "$hash"
}

need curl
need jq
need nix
need perl

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

targets=("$@")
if [[ "${#targets[@]}" -eq 0 || " ${targets[*]} " == *' all '* ]]; then
  targets=(opencode helium t3 oxc tsgo)
fi

for target in "${targets[@]}"; do
  case "$target" in
    opencode) update_opencode ;;
    helium) update_helium ;;
    t3) update_t3 ;;
    oxc|oxlint|oxfmt) update_oxc ;;
    tsgo|typescript-go|typescript-native) update_tsgo ;;
    *)
      printf 'Unknown target: %s\n\n' "$target" >&2
      usage >&2
      exit 1
      ;;
  esac
done

printf '\nDone. Review the diff, then rebuild with:\n'
printf '  sudo nixos-rebuild switch --flake path:%s#nixos\n' "$ROOT"
