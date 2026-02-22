#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FinderWrapNavigator"
BUNDLE_NAME="${APP_NAME}.app"
DIST_DIR="${PROJECT_DIR}/dist"
APP_DIR="${DIST_DIR}/${BUNDLE_NAME}"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICONSET_DIR="$(mktemp -d "${TMPDIR:-/tmp}/finderwrap.iconset.XXXXXX")/AppIcon.iconset"
DOWNLOADS_DIR="${HOME}/Downloads"

cleanup() {
  rm -rf "$(dirname "${ICONSET_DIR}")"
}
trap cleanup EXIT

find_latest_image() {
  find "${DOWNLOADS_DIR}" -maxdepth 1 -type f \
    \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.heic" -o -iname "*.tif" -o -iname "*.tiff" \) \
    -exec stat -f '%m %N' {} \; \
    | sort -rn \
    | head -n 1 \
    | cut -d' ' -f2-
}

ICON_SOURCE="${1:-}"
if [[ -z "${ICON_SOURCE}" ]]; then
  ICON_SOURCE="$(find_latest_image)"
fi

if [[ -z "${ICON_SOURCE}" || ! -f "${ICON_SOURCE}" ]]; then
  echo "Error: icon source image not found."
  echo "Usage: scripts/build_app.sh [path/to/icon.png]"
  exit 1
fi

echo "Icon source: ${ICON_SOURCE}"
echo "Building release binary..."
cd "${PROJECT_DIR}"
swift build -c release

BIN_PATH="${PROJECT_DIR}/.build/release/${APP_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
  echo "Error: release binary not found at ${BIN_PATH}"
  exit 1
fi

echo "Generating .icns..."
mkdir -p "${ICONSET_DIR}"
sips -z 16 16 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
sips -z 32 32 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
sips -z 64 64 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
sips -z 256 256 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
sips -z 512 512 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
sips -z 1024 1024 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null

mkdir -p "${DIST_DIR}"
iconutil -c icns "${ICONSET_DIR}" -o "${DIST_DIR}/AppIcon.icns"

echo "Packaging app bundle..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"
cp "${DIST_DIR}/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"

cat > "${CONTENTS_DIR}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>FinderWrap</string>
  <key>CFBundleExecutable</key>
  <string>FinderWrapNavigator</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.finderwrap.navigator</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>FinderWrapNavigator</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "Done."
echo "App bundle: ${APP_DIR}"
echo "Open with: open \"${APP_DIR}\""
