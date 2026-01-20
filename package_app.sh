#!/bin/bash

# 设置错误即停止
set -e

APP_NAME="WeChatVoiceRecorder"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Step 1: Building project in release mode..."
swift build -c release

echo "Step 2: Creating .app bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "Step 3: Copying binary, Info.plist and AppIcon..."
cp ".build/release/$APP_NAME" "$MACOS_DIR/"
cp "Sources/WeChatVoiceRecorder/Info.plist" "$CONTENTS_DIR/"
if [ -f "Sources/WeChatVoiceRecorder/Resources/AppIcon.icns" ]; then
    cp "Sources/WeChatVoiceRecorder/Resources/AppIcon.icns" "$RESOURCES_DIR/"
fi

echo "Step 4: Signing the application (ad-hoc)..."
# 使用 ad-hoc 签名，以便在本地运行并请求权限
codesign --force --deep --sign - "$APP_BUNDLE"

echo "------------------------------------------------"
echo "✅ 打包完成: $APP_BUNDLE"
echo "现在你可以通过以下方式运行:"
echo "open $APP_BUNDLE"
echo "------------------------------------------------"
