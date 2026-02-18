#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-v2.0.0}"
APP_NAME="Synapse"
BUNDLE_ID="com.oboy.neo-synapse"
MIN_MACOS="14.0"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/release"
DIST_DIR="$ROOT_DIR/dist/release/$VERSION"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ZIP_NAME="NeoSynapse-$VERSION-macos-arm64.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
ICON_ICNS_SRC="$ROOT_DIR/Sources/Synapse/Resources/AppIcon/Synapse.icns"

if [[ ! -f "$ICON_ICNS_SRC" ]]; then
  echo "Missing icon file: $ICON_ICNS_SRC" >&2
  exit 1
fi

echo "[1/6] Building release binary..."
cd "$ROOT_DIR"
swift build -c release

echo "[2/6] Preparing app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp -R "$BUILD_DIR/${APP_NAME}_Synapse.bundle" "$APP_DIR/Contents/Resources/"
cp "$ICON_ICNS_SRC" "$APP_DIR/Contents/Resources/Synapse.icns"

SHORT_VERSION="${VERSION#v}"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>Neo-Synapse</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$SHORT_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$SHORT_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS</string>
  <key>LSUIElement</key>
  <true/>
  <key>CFBundleIconFile</key>
  <string>Synapse</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Neo-Synapse needs Automation to run system commands and control apps.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Neo-Synapse needs Microphone for real-time speech recognition and Ray voice pet wake word.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Neo-Synapse needs Speech Recognition to convert voice commands to text.</string>
</dict>
</plist>
PLIST

chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

echo "[3/6] Codesigning (ad-hoc)..."
codesign --force --deep --sign - "$APP_DIR"

echo "[4/6] Creating release archive..."
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "[5/6] Packaging metadata..."
cp "$APP_DIR/Contents/Info.plist" "$DIST_DIR/Info.plist"

echo "[6/6] Writing checksums..."
cd "$DIST_DIR"
shasum -a 256 "$ZIP_NAME" "Info.plist" > SHA256SUMS.txt

cat <<MSG

Release assets generated:
- $ZIP_PATH
- $DIST_DIR/Info.plist
- $DIST_DIR/SHA256SUMS.txt

MSG
