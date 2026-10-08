#!/bin/sh
# Builds "Daytick.app" into mac/build/. Run from anywhere: ./mac/build.sh
set -e
cd "$(dirname "$0")"
APP="build/Daytick.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"

swiftc -O main.swift -o "$APP/Contents/MacOS/Daytick"
cp ../index.html ../icon.svg ../icon-512.png "$APP/Contents/Resources/web/"
cp -R ../fonts "$APP/Contents/Resources/web/"

# App icon from icon-512.png
ICONSET=build/AppIcon.iconset && mkdir -p $ICONSET
for s in 16 32 128 256 512; do
  sips -z $s $s ../icon-512.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) ../icon-512.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $ICONSET -o "$APP/Contents/Resources/AppIcon.icns" && rm -rf $ICONSET

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Daytick</string>
  <key>CFBundleIdentifier</key><string>io.github.o1ie12.todo</string>
  <key>CFBundleExecutable</key><string>Daytick</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
