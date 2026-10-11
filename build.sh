#!/bin/bash
# Сборка Counter Trade.app. Нужны только Command Line Tools.
#
#   ./build.sh          собрать build/Counter Trade.app
#   ./build.sh run      собрать и запустить отсюда
#   ./build.sh install  собрать, положить в ~/Applications и запустить
#   ./build.sh dmg      собрать build/Counter-Trade.dmg для раздачи
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Counter Trade.app"

echo "==> swift build"
swift build -c release --product Winrate
BIN="$(swift build -c release --show-bin-path)/Winrate"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Counter Trade"
strip -x "$APP/Contents/MacOS/Counter Trade"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
SIGN_ID="-"
security find-identity -v -p codesigning 2>/dev/null | grep -q "Local Dev Signing" && SIGN_ID="Local Dev Signing"
codesign --force --sign "$SIGN_ID" "$APP"
echo "==> готово: $APP"

case "${1:-}" in
dmg)
    STAGE="build/dmg"
    rm -rf "$STAGE" build/Counter-Trade.dmg
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "Counter Trade" -srcfolder "$STAGE" -ov -format UDZO build/Counter-Trade.dmg >/dev/null
    rm -rf "$STAGE"
    echo "==> dmg: build/Counter-Trade.dmg"
    ;;
run)
    pkill -x "Counter Trade" 2>/dev/null && sleep 0.5 || true
    open "$APP"
    ;;
install)
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
    pkill -x "Counter Trade" 2>/dev/null && sleep 0.5 || true
    rm -rf "$DEST/Counter Trade.app"
    cp -R "$APP" "$DEST/"
    echo "==> установлено: $DEST/Counter Trade.app"
    open "$DEST/Counter Trade.app"
    ;;
esac
