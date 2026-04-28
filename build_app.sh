#!/bin/bash
# Build script for Peripheral Battery macOS Application Bundle
# This uses the Xcode project output so the app bundle includes the widget extension.

set -e

APP_NAME="PeripheralBattery"
APP_BUNDLE="${APP_NAME}.app"
PROJECT_PATH="${APP_NAME}.xcodeproj"
SCHEME="${APP_NAME}"
DERIVED_DATA_PATH="/private/tmp/PeripheralBatteryDerived"
BUILT_APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Debug/${APP_BUNDLE}"
SIGNED_APP_BUNDLE="/tmp/${APP_BUNDLE}"

clear_path_xattrs() {
    local target="$1"
    xattr -cr "${target}" 2>/dev/null || true
    while IFS= read -r -d '' path; do
        xattr -c "$path" 2>/dev/null || true
        xattr -d com.apple.FinderInfo "$path" 2>/dev/null || true
        xattr -d 'com.apple.fileprovider.fpfs#P' "$path" 2>/dev/null || true
    done < <(find "${target}" -print0)
}

echo "=== Building Peripheral Battery ==="

echo "Removing previous Xcode build output..."
rm -rf "${DERIVED_DATA_PATH}"

echo "Building app bundle with Xcode..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration Debug \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  build

if [ ! -d "${BUILT_APP_PATH}" ]; then
    echo "Expected app bundle not found at ${BUILT_APP_PATH}" >&2
    exit 1
fi

echo "Copying built app bundle..."
rm -rf "${APP_BUNDLE}"
cp -R "${BUILT_APP_PATH}" "${APP_BUNDLE}"
clear_path_xattrs "${APP_BUNDLE}"

echo "Creating signed copy in /tmp..."
rm -rf "${SIGNED_APP_BUNDLE}"
cp -R "${BUILT_APP_PATH}" "${SIGNED_APP_BUNDLE}"
clear_path_xattrs "${SIGNED_APP_BUNDLE}"
codesign --force --deep -s - "${SIGNED_APP_BUNDLE}"
codesign --verify --deep --strict --verbose=2 "${SIGNED_APP_BUNDLE}"

echo ""
echo "=== Build Complete ==="
echo ""
echo "App bundle created: ${APP_BUNDLE}"
echo "Signed app bundle also created: ${SIGNED_APP_BUNDLE}"
echo ""
echo "This app bundle includes:"
echo "  - the host app"
echo "  - the embedded widget extension"
echo ""
echo "To install:"
echo "  1. Move ${APP_BUNDLE} to /Applications"
echo "  2. Open it from Applications"
echo "  3. Remove any older widget instance, then add the widget again"
echo ""
