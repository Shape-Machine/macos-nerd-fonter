#!/bin/sh
# Builds a release binary and wraps it into build/NerdFonter.app (ad-hoc signed).
#   VERSION=1.2.3   version shown in Finder and About (default 0.1.0)
#   UNIVERSAL=1     build for Apple silicon and Intel (slower; used for releases)
set -eu

cd "$(dirname "$0")/.."

NAME=NerdFonter
VERSION="${VERSION:-0.1.0}"
APP="build/$NAME.app"

if [ "${UNIVERSAL:-}" = 1 ]; then
    FLAGS="-c release --arch arm64 --arch x86_64"
else
    FLAGS="-c release"
fi
# shellcheck disable=SC2086
swift build $FLAGS
# shellcheck disable=SC2086
BIN="$(swift build $FLAGS --show-bin-path)/$NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Nerd Fonter</string>
    <key>CFBundleDisplayName</key><string>Nerd Fonter</string>
    <key>CFBundleIdentifier</key><string>com.shapemachine.NerdFonter</string>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP"
