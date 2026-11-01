#!/bin/zsh
# Baut die App und packt sie in „Mac Notche <Version>.dmg“ (mit Verknüpfung nach /Programme).
set -e
cd "$(dirname "$0")"
./bauen.sh
VERSION=$(defaults read "$PWD/build/Mac Notche.app/Contents/Info" CFBundleShortVersionString)
ZIEL="../Mac Notche $VERSION.dmg"
STAGE=$(mktemp -d)
ditto "build/Mac Notche.app" "$STAGE/Mac Notche.app"
ln -s /Applications "$STAGE/Programme"
hdiutil create -volname "Mac Notche $VERSION" -srcfolder "$STAGE" -ov -format UDZO -quiet "$ZIEL"
echo "Fertig: $(cd .. && pwd)/Mac Notche $VERSION.dmg"
