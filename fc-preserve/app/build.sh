#!/bin/bash
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SRC/../.." && pwd)"
APP="${1:-$ROOT/dist/FC-Preserve.app}"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SRC/Info.plist" "$APP/Contents/Info.plist"
printf 'APPLFCPR' > "$APP/Contents/PkgInfo"
echo "swiftc $SRC/main.swift -> $APP"
/usr/bin/swiftc \
  -swift-version 5 \
  -sdk "$SDK" \
  -target "${ARCH}-apple-macosx13.0" \
  -O \
  -o "$APP/Contents/MacOS/FC-Preserve" \
  "$SRC/main.swift"
chmod +x "$APP/Contents/MacOS/FC-Preserve"
if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP" 2>/dev/null || true
fi
echo "built $APP"
