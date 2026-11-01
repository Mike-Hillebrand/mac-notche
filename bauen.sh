#!/bin/zsh
# Baut „Mac Notche.app“ nach ./build. Feste Signatur → macOS-Erlaubnisse bleiben über Neubauten erhalten.
set -e
cd "$(dirname "$0")"
swift build -c release
APP="build/Mac Notche.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MacNotche "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
mkdir -p "$APP/Contents/Resources" && cp AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
if [ -d Gesicht.mlmodelc ]; then cp -R Gesicht.mlmodelc "$APP/Contents/Resources/"; fi
codesign --force --sign "${KERBE_IDENTITAET:-Apple Development: hello@mikehillebrand.com}" "$APP" 2>/dev/null \
  || codesign --force --sign - "$APP"
echo "Fertig: $PWD/$APP"
