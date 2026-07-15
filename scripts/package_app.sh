#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP="$ROOT/build/Desktop Destroyer.app"
CONTENTS="$APP/Contents"

cd "$ROOT"
swift build -c "$CONFIGURATION"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/$CONFIGURATION/DesktopDestroyer" "$CONTENTS/MacOS/DesktopDestroyer"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
mkdir -p "$CONTENTS/Resources/Assets"
cp "$ROOT"/Resources/Assets/generated/*.png "$CONTENTS/Resources/Assets/"
rm -rf "$CONTENTS/Resources/Sounds"
cp -R "$ROOT/Resources/Sounds" "$CONTENTS/Resources/Sounds"
cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
chmod +x "$CONTENTS/MacOS/DesktopDestroyer"

/usr/bin/codesign --force --deep --sign - "$APP"
echo "$APP"
