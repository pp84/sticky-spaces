#!/bin/bash
# Builds build/StickySpaces.app. Signs with the first Apple Development identity so the
# Accessibility permission survives rebuilds (ad-hoc signatures change every build).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/StickySpaces.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/StickySpaces "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.punitpatel.StickySpaces</string>
    <key>CFBundleName</key><string>StickySpaces</string>
    <key>CFBundleExecutable</key><string>StickySpaces</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

IDENTITY=$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed with ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "install" ]]; then
    pkill -x StickySpaces || true
    rm -rf /Applications/StickySpaces.app
    cp -R "$APP" /Applications/
    open /Applications/StickySpaces.app
    echo "Installed and launched /Applications/StickySpaces.app"
fi
