#!/bin/bash
set -e

APP_NAME="Writedown"
SCHEME="Writedown"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/Export"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"

# Extract Version Info
echo "🔍 Reading version info..."
VERSION_SETTINGS=$(xcodebuild -scheme "$SCHEME" -showBuildSettings 2>/dev/null)
MARKETING_VERSION=$(echo "$VERSION_SETTINGS" | grep "MARKETING_VERSION =" | cut -d '=' -f 2 | xargs)
CURRENT_PROJECT_VERSION=$(echo "$VERSION_SETTINGS" | grep "CURRENT_PROJECT_VERSION =" | cut -d '=' -f 2 | xargs)

if [ -z "$MARKETING_VERSION" ]; then
    echo "⚠️  Could not detect version. Using default."
    FULL_VERSION="unknown"
else
    echo "ℹ️  App Version: $MARKETING_VERSION"
    echo "ℹ️  Build Number: $CURRENT_PROJECT_VERSION"
    FULL_VERSION="$MARKETING_VERSION"
fi

echo "🧹 Cleaning..."
rm -rf "$BUILD_DIR"

echo "🏗️  Archiving $APP_NAME ($FULL_VERSION)..."
xcodebuild -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination 'generic/platform=macOS' \
    archive \
    -quiet

echo "📦 Packaging..."
mkdir -p "$EXPORT_PATH"
# Direct copy from archive
cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$EXPORT_PATH/"

echo "🤐 Zipping..."
cd "$EXPORT_PATH"
zip -r -q "$APP_NAME.zip" "$APP_NAME.app"
cd - > /dev/null
mv "$EXPORT_PATH/$APP_NAME.zip" "$ZIP_PATH"

echo "✅ Package created at: $ZIP_PATH"
echo "   Version: $FULL_VERSION (Build $CURRENT_PROJECT_VERSION)"
echo "👉 Ready to upload to GitHub Release."
