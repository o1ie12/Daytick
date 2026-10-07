#!/bin/sh
# Builds the app and wraps it in a drag-to-Applications disk image: mac/build/ToDo-<version>.dmg
set -e
cd "$(dirname "$0")"
./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "build/To Do.app/Contents/Info.plist")
STAGE=build/dmg && rm -rf $STAGE && mkdir -p $STAGE
cp -R "build/To Do.app" $STAGE/
ln -s /Applications $STAGE/Applications
DMG="build/ToDo-$VERSION.dmg" && rm -f "$DMG"
hdiutil create -volname "To Do" -srcfolder $STAGE -ov -format UDZO "$DMG" >/dev/null
rm -rf $STAGE
echo "Packaged $DMG"
