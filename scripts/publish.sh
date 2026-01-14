#!/bin/bash
set -e

# Load environment variables if .env exists
if [ -f .env ]; then
    export $(cat .env | xargs)
fi

VERSION=$1


echo "🚀 Starting release process for version $VERSION..."

# 1. Bump Version (Optional)
if [ ! -z "$VERSION" ]; then
    echo "📈 Bumping version to $VERSION..."
    
    # Update Info.plist directly first
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "Writedown-Info.plist"
    
    # Update project.pbxproj MARKETING_VERSION to ensure xcodebuild picks it up
    # This is crucial because xcodebuild prioritizes Build Settings over Info.plist
    echo "🔧 Updating MARKETING_VERSION in project file..."
    sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = $VERSION;/g" Writedown.xcodeproj/project.pbxproj
    
    # Set build number to 1
    xcrun agvtool new-version -all 1
else
    echo "ℹ️  No version argument provided. Using current project version."
fi

# 2. Package (Build & Zip)
echo "📦 Packaging..."
./scripts/package.sh

# 3. Detect Version from Built Artifact (Source of Truth)
# We read the Info.plist from the actual built .app file to ensure consistency
BUILT_APP_PLIST="build/Export/Writedown.app/Contents/Info.plist"

if [ ! -f "$BUILT_APP_PLIST" ]; then
    echo "❌ Error: Built app Info.plist not found at $BUILT_APP_PLIST"
    echo "   Did the package script fail?"
    exit 1
fi

DETECTED_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$BUILT_APP_PLIST")

if [ -z "$DETECTED_VERSION" ]; then
    echo "❌ Error: Could not read version from built app."
    exit 1
fi

echo "✅ Verified built artifact version: $DETECTED_VERSION"

# 4. Upload to Vercel Blob using the DETECTED version
echo "☁️ Uploading to Vercel Blob..."

if [ -z "$BLOB_READ_WRITE_TOKEN" ]; then
    echo "❌ Error: BLOB_READ_WRITE_TOKEN is not set."
    echo "Please set it in .env file or export it in your shell."
    exit 1
fi

# Pass the detected version, NOT the input argument
node scripts/upload-release.js "$DETECTED_VERSION"

echo "✅ Release $DETECTED_VERSION published successfully!"
