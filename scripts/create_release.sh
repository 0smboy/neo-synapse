#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-v1.3.1}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/release/$VERSION"
NOTES_FILE="$ROOT_DIR/docs/releases/${VERSION}.md"

if [[ ! -f "$NOTES_FILE" ]]; then
  echo "Missing release notes: $NOTES_FILE" >&2
  exit 1
fi

if [[ ! -f "$DIST_DIR/Synapse-${VERSION}-macos-arm64.zip" ]]; then
  echo "Release assets missing. Running package script..."
  "$ROOT_DIR/scripts/package_release.sh" "$VERSION"
fi

cd "$ROOT_DIR"

if ! git rev-parse "$VERSION" >/dev/null 2>&1; then
  git tag "$VERSION"
fi

gh release create "$VERSION" \
  --title "Synapse ${VERSION}" \
  --notes-file "$NOTES_FILE" \
  "$DIST_DIR/Synapse-${VERSION}-macos-arm64.zip" \
  "$DIST_DIR/Info.plist" \
  "$DIST_DIR/SHA256SUMS.txt"

echo "Release published: $VERSION"
