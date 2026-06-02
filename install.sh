#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PromptFirefly"
BUNDLE_ID="com.shokhabbos.PromptFirefly"
APP_VERSION="0.11.2"
APP_BUILD="112"
REPO_URL="${PROMPT_FIREFLY_REPO_URL:-https://github.com/skverall/prompt-firefly.git}"
INSTALL_ROOT="${PROMPT_FIREFLY_HOME:-$HOME/.prompt-firefly}"
SOURCE_DIR="$INSTALL_ROOT/source"
APP_DIR="${PROMPT_FIREFLY_APP_DIR:-$HOME/Applications}"
APP_BUNDLE="$APP_DIR/$APP_NAME.app"

print_step() {
  printf "\n\033[1;32m==>\033[0m %s\n" "$1"
}

print_note() {
  printf "   %s\n" "$1"
}

fail() {
  printf "\n\033[1;31mError:\033[0m %s\n" "$1" >&2
  exit 1
}

open_accessibility_settings() {
  /usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" >/dev/null 2>&1 || true
}

uninstall() {
  print_step "Stopping Prompt Firefly"
  /usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true

  print_step "Removing app and local source"
  /bin/rm -rf "$APP_BUNDLE" "$INSTALL_ROOT"

  print_note "Prompt Firefly was removed from $APP_BUNDLE"
  print_note "You can also remove its Accessibility permission in System Settings if you want."
}

if [[ "${1:-}" == "--uninstall" ]]; then
  uninstall
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "Prompt Firefly currently supports macOS only."
fi

print_step "Checking required tools"

if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
  print_note "Apple Command Line Tools are needed to build the app."
  print_note "macOS will open the installer now. After it finishes, run this install command again."
  /usr/bin/xcode-select --install >/dev/null 2>&1 || true
  exit 0
fi

command -v git >/dev/null 2>&1 || fail "git is missing. Install Apple Command Line Tools, then try again."
command -v swift >/dev/null 2>&1 || fail "swift is missing. Install Apple Command Line Tools, then try again."

print_step "Downloading Prompt Firefly"
/bin/mkdir -p "$INSTALL_ROOT"

if [[ -d "$SOURCE_DIR/.git" ]]; then
  print_note "Updating existing source at $SOURCE_DIR"
  /usr/bin/git -C "$SOURCE_DIR" pull --ff-only
elif [[ -e "$SOURCE_DIR" ]]; then
  BACKUP_DIR="$SOURCE_DIR.backup.$(date +%Y%m%d%H%M%S)"
  print_note "Existing non-git folder found. Moving it to $BACKUP_DIR"
  /bin/mv "$SOURCE_DIR" "$BACKUP_DIR"
  /usr/bin/git clone --depth 1 "$REPO_URL" "$SOURCE_DIR"
else
  /usr/bin/git clone --depth 1 "$REPO_URL" "$SOURCE_DIR"
fi

print_step "Building release app"
/usr/bin/swift build -c release --package-path "$SOURCE_DIR"
BUILD_BINARY="$(/usr/bin/swift build -c release --package-path "$SOURCE_DIR" --show-bin-path)/$APP_NAME"

[[ -x "$BUILD_BINARY" ]] || fail "Build finished, but the app binary was not found."

print_step "Installing to $APP_BUNDLE"
/usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true

APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"

/bin/rm -rf "$APP_BUNDLE"
/bin/mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_DIR"
/bin/cp "$BUILD_BINARY" "$APP_BINARY"
/bin/chmod +x "$APP_BINARY"

if [[ -f "$SOURCE_DIR/docs/assets/AppIcon.icns" ]]; then
  /bin/cp "$SOURCE_DIR/docs/assets/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
elif [[ -f "$SOURCE_DIR/docs/assets/icon.png" ]]; then
  /bin/cp "$SOURCE_DIR/docs/assets/icon.png" "$APP_RESOURCES/AppIcon.png"
fi

/bin/cat >"$APP_CONTENTS/Info.plist" <<PLIST
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
  <string>14.0</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Prompt Firefly reads the current Terminal command so it can suggest a safer corrected version before you run it.</string>
  <key>NSHumanReadableCopyright</key>
  <string>Prompt Firefly is an open-source local prompt rewriting tool.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

print_step "Signing app locally"
/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null

if [[ "${PROMPT_FIREFLY_NO_OPEN:-0}" == "1" ]]; then
  print_step "Skipping launch because PROMPT_FIREFLY_NO_OPEN=1"
else
  print_step "Launching Prompt Firefly"
  /usr/bin/open -n "$APP_BUNDLE"

  print_step "Opening Accessibility settings"
  open_accessibility_settings
fi

cat <<DONE

Prompt Firefly is installed.

Next steps:
1. In System Settings -> Privacy & Security -> Accessibility, turn on PromptFirefly.
2. Open Prompt Firefly settings, paste your DeepSeek API key, then click Save.
3. Click inside Codex, Terminal, Telegram, or any text field and press the firefly button.

Terminal safety:
- Prompt Firefly replaces the current command line only.
- It does not press Enter. You review the command and run it yourself.

Update later:
  /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/skverall/prompt-firefly/main/install.sh)"

Uninstall:
  /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/skverall/prompt-firefly/main/install.sh)" -- --uninstall

DONE
