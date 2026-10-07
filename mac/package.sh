#!/bin/sh
# Builds the app and wraps it in a drag-to-Applications disk image: mac/build/Daytick-<version>.dmg
set -e
cd "$(dirname "$0")"
./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "build/Daytick.app/Contents/Info.plist")
STAGE=build/dmg && rm -rf $STAGE && mkdir -p $STAGE
cp -R "build/Daytick.app" $STAGE/
ln -s /Applications $STAGE/Applications
DMG="build/Daytick-$VERSION.dmg" && rm -f "$DMG"
hdiutil create -volname "Daytick" -srcfolder $STAGE -ov -format UDZO "$DMG" >/dev/null
rm -rf $STAGE
echo "Packaged $DMG"
