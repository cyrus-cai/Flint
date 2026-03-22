#!/bin/bash
set -e

# Configuration
REPO="cyrus-cai/Flint"
APP_NAME="Flint"
INSTALL_DIR="/Applications"
TEMP_DIR=$(mktemp -d)

echo "⬇️  Downloading $APP_NAME..."

# Get the latest release download URL
# Assumes the asset is named "$APP_NAME.zip"
LATEST_URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep "browser_download_url.*$APP_NAME.zip" | cut -d '"' -f 4)

if [ -z "$LATEST_URL" ]; then
    echo "❌ Error: Could not find latest release for $APP_NAME."
    exit 1
fi

# Download the zip file
curl -fsSL "$LATEST_URL" -o "$TEMP_DIR/$APP_NAME.zip"

echo "📦 Installing to $INSTALL_DIR..."

# Unzip
unzip -q "$TEMP_DIR/$APP_NAME.zip" -d "$TEMP_DIR"

# Remove existing app if present
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo "♻️  Replacing existing installation..."
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi

# Move app to Applications
mv "$TEMP_DIR/$APP_NAME.app" "$INSTALL_DIR/"

# Cleanup
rm -rf "$TEMP_DIR"

# Set up CLI symlink
CLI_PATH="$INSTALL_DIR/$APP_NAME.app/Contents/Resources/flint-cli"
if [ -f "$CLI_PATH" ]; then
    # Prefer ~/.local/bin (no sudo), fall back to /usr/local/bin
    for BIN_DIR in "$HOME/.local/bin" "/usr/local/bin"; do
        mkdir -p "$BIN_DIR" 2>/dev/null && \
        ln -sf "$CLI_PATH" "$BIN_DIR/flint" 2>/dev/null && \
        echo "🔧 CLI installed: $BIN_DIR/flint" && break
    done
fi

echo "✅ $APP_NAME successfully installed!"
echo "🎉 You can now find it in your Applications folder."
