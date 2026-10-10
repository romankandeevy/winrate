#!/bin/bash
# Сборка Winrate.app. Нужны только Command Line Tools.
#
#   ./build.sh          собрать build/Winrate.app
#   ./build.sh run      собрать и запустить отсюда
#   ./build.sh install  собрать, положить в ~/Applications и запустить
#   ./build.sh dmg      собрать build/Winrate.dmg для раздачи
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Winrate.app"

echo "==> swift build"
swift build -c release --product Winrate
BIN="$(swift build -c release --show-bin-path)/Winrate"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Winrate"
strip -x "$APP/Contents/MacOS/Winrate"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
SIGN_ID="-"
security find-identity -v -p codesigning 2>/dev/null | grep -q "Local Dev Signing" && SIGN_ID="Local Dev Signing"
codesign --force --sign "$SIGN_ID" "$APP"
echo "==> готово: $APP"

case "${1:-}" in
dmg)
    STAGE="build/dmg"
    rm -rf "$STAGE" build/Winrate.dmg
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "Winrate" -srcfolder "$STAGE" -ov -format UDZO build/Winrate.dmg >/dev/null
    rm -rf "$STAGE"
    echo "==> dmg: build/Winrate.dmg"
    ;;
run)
    pkill -x Winrate 2>/dev/null && sleep 0.5 || true
    open "$APP"
    ;;
install)
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
    pkill -x Winrate 2>/dev/null && sleep 0.5 || true
    rm -rf "$DEST/Winrate.app"
    cp -R "$APP" "$DEST/"
    echo "==> установлено: $DEST/Winrate.app"
    open "$DEST/Winrate.app"
    ;;
esac
