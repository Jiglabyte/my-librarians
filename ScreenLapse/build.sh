#!/usr/bin/env bash
# ScreenLapse build helper.
#   ./build.sh            generate Xcode project and build Debug
#   ./build.sh release    generate and build Release into ./build/
#   ./build.sh run        generate, build Debug, and launch the app
#   ./build.sh dmg        build Release and package as ScreenLapse.dmg
#   ./build.sh clean      delete build artifacts

set -euo pipefail
cd "$(dirname "$0")"

CMD="${1:-debug}"

require_xcodegen() {
    if ! command -v xcodegen >/dev/null 2>&1; then
        echo "error: xcodegen is not installed."
        echo "install it with: brew install xcodegen"
        exit 1
    fi
}

require_xcodebuild() {
    if ! command -v xcodebuild >/dev/null 2>&1; then
        echo "error: xcodebuild not found. Install Xcode from the App Store."
        exit 1
    fi
}

ensure_icon() {
    local sentinel="ScreenLapse/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
    if [[ ! -f "$sentinel" ]]; then
        echo "==> generating app icon (first run)"
        swift create_icon.swift
    fi
}

generate() {
    require_xcodegen
    ensure_icon
    echo "==> generating ScreenLapse.xcodeproj"
    xcodegen generate
}

case "$CMD" in
    clean)
        rm -rf build ScreenLapse.xcodeproj
        echo "==> cleaned"
        ;;
    debug)
        generate
        require_xcodebuild
        echo "==> building Debug"
        xcodebuild \
            -project ScreenLapse.xcodeproj \
            -scheme ScreenLapse \
            -configuration Debug \
            -derivedDataPath build/DerivedData \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            build
        ;;
    release)
        generate
        require_xcodebuild
        echo "==> building Release"
        xcodebuild \
            -project ScreenLapse.xcodeproj \
            -scheme ScreenLapse \
            -configuration Release \
            -derivedDataPath build/DerivedData \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            build
        APP_PATH="build/DerivedData/Build/Products/Release/ScreenLapse.app"
        if [[ -d "$APP_PATH" ]]; then
            mkdir -p build
            cp -R "$APP_PATH" build/
            echo "==> built: build/ScreenLapse.app"
        fi
        ;;
    run)
        "$0" debug
        APP_PATH="build/DerivedData/Build/Products/Debug/ScreenLapse.app"
        echo "==> stopping any running instance"
        osascript -e 'tell application "ScreenLapse" to quit' >/dev/null 2>&1 || true
        pkill -x ScreenLapse 2>/dev/null || true
        sleep 0.3
        echo "==> launching $APP_PATH"
        open "$APP_PATH"
        ;;
    dmg)
        "$0" release
        APP_PATH="build/ScreenLapse.app"
        if [[ ! -d "$APP_PATH" ]]; then
            echo "error: $APP_PATH not found after release build."
            exit 1
        fi

        VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1.0.0")
        DMG_NAME="ScreenLapse-$VERSION.dmg"
        STAGING="build/dmg-staging"
        DMG_OUT="build/$DMG_NAME"

        echo "==> staging $STAGING"
        rm -rf "$STAGING" "$DMG_OUT"
        mkdir -p "$STAGING"
        cp -R "$APP_PATH" "$STAGING/"
        ln -s /Applications "$STAGING/Applications"

        echo "==> creating $DMG_OUT"
        hdiutil create \
            -volname "ScreenLapse" \
            -srcfolder "$STAGING" \
            -ov \
            -format UDZO \
            -fs HFS+ \
            "$DMG_OUT"

        rm -rf "$STAGING"
        echo ""
        echo "============================================"
        echo "  DMG ready:  $DMG_OUT"
        echo "  Open with:  open $DMG_OUT"
        echo "============================================"
        ;;
    *)
        echo "usage: $0 {debug|release|run|dmg|clean}"
        exit 2
        ;;
esac
