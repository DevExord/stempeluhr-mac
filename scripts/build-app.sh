#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds Stempeluhr.app — a menu-bar time clock — from the Swift package.
#
#   scripts/build-app.sh [release|debug]   (default: release)
#
# Output: macos/build/Stempeluhr.app  (ad-hoc signed so it runs locally).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Stempeluhr.app"

echo "→ swift build -c $CONFIG"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Stempeluhr"

echo "→ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/Stempeluhr"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "→ ad-hoc code signing"
codesign --force --sign - "$APP" >/dev/null 2>&1 || \
  echo "  (codesign skipped — the app still runs, but Keychain may re-prompt)"

echo "✓ Built $APP"
echo "  Run it with:  open \"$PWD/$APP\""
