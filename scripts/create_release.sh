#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-v2.0.0}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/release/$VERSION"
NOTES_FILE="$ROOT_DIR/docs/releases/${VERSION}.md"
ZIP_NAME="NeoSynapse-${VERSION}-macos-arm64.zip"

if [[ ! -f "$NOTES_FILE" ]]; then
  echo "Missing release notes: $NOTES_FILE" >&2
  exit 1
fi

if [[ ! -f "$DIST_DIR/$ZIP_NAME" ]]; then
  echo "Release assets missing. Running package script..."
  "$ROOT_DIR/scripts/package_release.sh" "$VERSION"
fi

cd "$ROOT_DIR"

if ! git rev-parse "$VERSION" >/dev/null 2>&1; then
  git tag "$VERSION"
fi

gh release create "$VERSION" \
  --repo 0smboy/neo-synapse \
  --title "Neo-Synapse ${VERSION}" \
  --notes-file "$NOTES_FILE" \
  "$DIST_DIR/$ZIP_NAME" \
  "$DIST_DIR/Info.plist" \
  "$DIST_DIR/SHA256SUMS.txt"

echo "Release published: $VERSION"
