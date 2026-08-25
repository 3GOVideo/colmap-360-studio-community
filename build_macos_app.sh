#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SOURCE="$SCRIPT_DIR/macos-app"
DIST_DIR="$SCRIPT_DIR/dist"
APP_DIR="$DIST_DIR/COLMAP 360 Studio.app"
CONTENTS="$APP_DIR/Contents"
RESOURCES="$CONTENTS/Resources"
PIPELINE="$RESOURCES/Pipeline"
BUILD_CACHE="$APP_SOURCE/.local-build-cache"

mkdir -p "$BUILD_CACHE/clang" "$BUILD_CACHE/swiftpm"
export CLANG_MODULE_CACHE_PATH="$BUILD_CACHE/clang"
export XDG_CACHE_HOME="$BUILD_CACHE"

echo "Compilando COLMAP 360 Studio…"
swift build --disable-sandbox --package-path "$APP_SOURCE" --scratch-path "$APP_SOURCE/.build" -c release
BIN_DIR="$(swift build --disable-sandbox --package-path "$APP_SOURCE" --scratch-path "$APP_SOURCE/.build" -c release --show-bin-path)"

mkdir -p "$CONTENTS/MacOS" "$PIPELINE"
cp "$BIN_DIR/COLMAP360Studio" "$CONTENTS/MacOS/COLMAP360Studio"
cp "$APP_SOURCE/Info.plist" "$CONTENTS/Info.plist"
cp "$SCRIPT_DIR/process_video.py" "$PIPELINE/process_video.py"
cp "$SCRIPT_DIR/brush_runner.py" "$PIPELINE/brush_runner.py"
cp "$SCRIPT_DIR/reconstruct_360.py" "$PIPELINE/reconstruct_360.py"
cp "$SCRIPT_DIR/reconstruct_flat.py" "$PIPELINE/reconstruct_flat.py"
cp "$SCRIPT_DIR/panorama_sfm_4_1_1.py" "$PIPELINE/panorama_sfm_4_1_1.py"
cp "$SCRIPT_DIR/requirements.txt" "$PIPELINE/requirements.txt"
cp "$SCRIPT_DIR/setup_macos.sh" "$PIPELINE/setup_macos.sh"
cp "$APP_SOURCE/Assets/app-icon.png" "$RESOURCES/AppIcon.png"
chmod +x "$CONTENTS/MacOS/COLMAP360Studio" "$PIPELINE"/*.py "$PIPELINE"/*.sh

ICON_SOURCE="$APP_SOURCE/Assets/app-icon.png"
if [[ -f "$ICON_SOURCE" ]]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  python3 "$APP_SOURCE/make_icns.py" "$ICONSET" "$RESOURCES/AppIcon.icns"
fi

codesign --force --deep --sign - "$APP_DIR"
echo "✓ App creada en: $APP_DIR"
