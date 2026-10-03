#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
APP_PATH="$PROJECT_ROOT/格式工厂.app"
BUILD_DIR="$PROJECT_ROOT/.build/app-bundle"
MODULE_CACHE="$PROJECT_ROOT/.build/objc-module-cache"
BUILD_VARIANT="${FORMAT_FACTORY_BUILD_VARIANT:-auto}"

cd "$PROJECT_ROOT"

mkdir -p "$BUILD_DIR" "$MODULE_CACHE"
EXECUTABLE_PATH=""

if [[ "$BUILD_VARIANT" == "swift" || ( "$BUILD_VARIANT" == "auto" && -d /Applications/Xcode.app ) ]]; then
    echo "使用 SwiftUI 构建…"
    swift build -c release --product FormatFactoryApp
    SWIFT_BIN_PATH="$(swift build -c release --show-bin-path)"
    EXECUTABLE_PATH="$SWIFT_BIN_PATH/FormatFactoryApp"
else
    echo "使用原生 AppKit 后备构建（当前未检测到完整 Xcode）…"
    clang \
        -fobjc-arc \
        -fmodules \
        -fmodules-cache-path="$MODULE_CACHE" \
        -mmacosx-version-min=13.0 \
        NativeFallback/FFConversionEngine.m \
        NativeFallback/FFApp.m \
        -o "$BUILD_DIR/FormatFactoryApp" \
        -framework AppKit \
        -framework Foundation \
        -framework CoreGraphics \
        -framework ImageIO \
        -framework PDFKit \
        -framework UniformTypeIdentifiers
    EXECUTABLE_PATH="$BUILD_DIR/FormatFactoryApp"
fi

if [[ -e "$APP_PATH" && "$APP_PATH" != "$PROJECT_ROOT/格式工厂.app" ]]; then
    echo "拒绝清理意外路径：$APP_PATH" >&2
    exit 1
fi

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$EXECUTABLE_PATH" "$APP_PATH/Contents/MacOS/FormatFactoryApp"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
chmod 755 "$APP_PATH/Contents/MacOS/FormatFactoryApp"

plutil -lint "$APP_PATH/Contents/Info.plist"
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "已生成：$APP_PATH"
