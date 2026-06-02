#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="PromptFirefly"
BUNDLE_ID="com.shokhabbos.PromptFirefly"
APP_VERSION="0.11.2"
APP_BUILD="112"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
printf "%s\n" "$ROOT_DIR" >"$APP_RESOURCES/default-context.txt"

if [[ -f "$ROOT_DIR/docs/assets/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/docs/assets/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
elif [[ -f "$ROOT_DIR/docs/assets/icon.png" ]]; then
  cp "$ROOT_DIR/docs/assets/icon.png" "$APP_RESOURCES/AppIcon.png"
elif [[ -f "$ROOT_DIR/work/promptfirefly-icon-512x512.png" ]]; then
  cp "$ROOT_DIR/work/promptfirefly-icon-512x512.png" "$APP_RESOURCES/AppIcon.png"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>Prompt Firefly</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Prompt Firefly reads the current Terminal command so it can suggest a safer corrected version before you run it.</string>
  <key>NSHumanReadableCopyright</key>
  <string>Prompt Firefly is an open-source local prompt rewriting tool.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

SIGN_IDENTITY="$(
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/awk -F '"' '/Apple Development/ { print $2; exit }'
)"

if [[ -n "$SIGN_IDENTITY" ]]; then
  /usr/bin/codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE" >/dev/null
  echo "Signed with: $SIGN_IDENTITY"
else
  /usr/bin/codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
  echo "Signed with: ad-hoc fallback"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
