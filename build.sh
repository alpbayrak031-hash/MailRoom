#!/bin/bash
# Builds Mailroom and assembles dist/Mailroom.app.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

if [ ! -f Support/AppIcon.icns ]; then
    work="$(mktemp -d)"
    swift Support/make_icon.swift "$work/icon.png"
    mkdir "$work/AppIcon.iconset"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$work/icon.png" --out "$work/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
        sips -z "$((size * 2))" "$((size * 2))" "$work/icon.png" --out "$work/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$work/AppIcon.iconset" -o Support/AppIcon.icns
fi

app="dist/Mailroom.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Mailroom "$app/Contents/MacOS/Mailroom"
# Debug symbols carry this machine's source paths; leave them out of the bundle.
strip -S "$app/Contents/MacOS/Mailroom" 2>/dev/null
cp Support/Info.plist "$app/Contents/Info.plist"
cp Support/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app" 2>/dev/null

echo "Built $app"
