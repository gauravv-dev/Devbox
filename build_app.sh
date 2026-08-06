#!/bin/bash
set -euo pipefail

# Builds Devbox and assembles an unsigned .app bundle at build/Devbox.app
cd "$(dirname "$0")"

CONFIG="release"
echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/Devbox"
APP="build/Devbox.app"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Devbox"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc sign so Gatekeeper doesn't block local launches
if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "==> Done: $(pwd)/$APP"
echo "    Run with: open $APP"
