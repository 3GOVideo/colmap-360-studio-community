#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SOURCE="$SCRIPT_DIR/macos-app"
DIST_DIR="$SCRIPT_DIR/dist"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_SOURCE/Info.plist")"
APP_RELEASE_LABEL="v$APP_VERSION"
APP_DIR="$DIST_DIR/COLMAP 360 Studio $APP_RELEASE_LABEL.app"
CONTENTS="$APP_DIR/Contents"
RESOURCES="$CONTENTS/Resources"
PIPELINE="$RESOURCES/Pipeline"
SUPERSPLAT_SOURCE="$SCRIPT_DIR/supersplat-viewer/node_modules/@playcanvas/supersplat-viewer/public"
SUPERSPLAT_RESOURCES="$RESOURCES/SuperSplat"
BUILD_CACHE="$APP_SOURCE/.local-build-cache"

mkdir -p "$BUILD_CACHE/clang" "$BUILD_CACHE/swiftpm"
export CLANG_MODULE_CACHE_PATH="$BUILD_CACHE/clang"
export XDG_CACHE_HOME="$BUILD_CACHE"

echo "Compilando COLMAP 360 Studio…"
swift build --disable-sandbox --package-path "$APP_SOURCE" --scratch-path "$APP_SOURCE/.build" -c release
BIN_DIR="$(swift build --disable-sandbox --package-path "$APP_SOURCE" --scratch-path "$APP_SOURCE/.build" -c release --show-bin-path)"

if [[ ! -f "$SUPERSPLAT_SOURCE/index.js" ]]; then
  echo "Preparando el visor SuperSplat…"
  npm install --prefix "$SCRIPT_DIR/supersplat-viewer"
fi

mkdir -p "$CONTENTS/MacOS" "$PIPELINE" "$SUPERSPLAT_RESOURCES"
if [[ -d "$PIPELINE/__pycache__" ]]; then
  rm -rf "$PIPELINE/__pycache__"
fi
cp "$BIN_DIR/COLMAP360Studio" "$CONTENTS/MacOS/COLMAP360Studio"
cp "$APP_SOURCE/Info.plist" "$CONTENTS/Info.plist"
cp "$SCRIPT_DIR/process_video.py" "$PIPELINE/process_video.py"
cp "$SCRIPT_DIR/runtime_support.py" "$PIPELINE/runtime_support.py"
cp "$SCRIPT_DIR/brush_runner.py" "$PIPELINE/brush_runner.py"
cp "$SCRIPT_DIR/reconstruct_360.py" "$PIPELINE/reconstruct_360.py"
cp "$SCRIPT_DIR/reconstruct_flat.py" "$PIPELINE/reconstruct_flat.py"
cp "$SCRIPT_DIR/panorama_sfm_4_1_1.py" "$PIPELINE/panorama_sfm_4_1_1.py"
cp "$SCRIPT_DIR/requirements.txt" "$PIPELINE/requirements.txt"
cp "$SCRIPT_DIR/setup_macos.sh" "$PIPELINE/setup_macos.sh"
cp "$APP_SOURCE/Assets/app-icon.png" "$RESOURCES/AppIcon.png"
cp "$SUPERSPLAT_SOURCE/index.html" "$SUPERSPLAT_RESOURCES/index.html"
cp "$SUPERSPLAT_SOURCE/index.css" "$SUPERSPLAT_RESOURCES/index.css"
cp "$SUPERSPLAT_SOURCE/index.js" "$SUPERSPLAT_RESOURCES/index.js"
cp "$SCRIPT_DIR/supersplat-viewer/settings.json" "$SUPERSPLAT_RESOURCES/settings.json"
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
