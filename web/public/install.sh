#!/bin/bash
set -e

APP_NAME="Flint"
DOWNLOAD_URL="https://wfcpsam37fc4yuvn.public.blob.vercel-storage.com/Flint-latest.zip"
INSTALL_DIR="/Applications"
TEMP_DIR=$(mktemp -d)

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Downloading ${APP_NAME}...${NC}"
curl -L -o "$TEMP_DIR/$APP_NAME.zip" "$DOWNLOAD_URL"

echo -e "${BLUE}Installing to $INSTALL_DIR...${NC}"
unzip -q "$TEMP_DIR/$APP_NAME.zip" -d "$TEMP_DIR"

if [ -d "$TEMP_DIR/$APP_NAME.app" ]; then
    SOURCE_APP="$TEMP_DIR/$APP_NAME.app"
else
    SOURCE_APP=$(find "$TEMP_DIR" -name "*.app" | head -n 1)
fi

if [ -z "$SOURCE_APP" ]; then
    echo "Error: Could not find .app in the downloaded archive."
    exit 1
fi

if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi

mv "$SOURCE_APP" "$INSTALL_DIR/"

echo -e "${BLUE}Cleaning up...${NC}"
rm -rf "$TEMP_DIR"

echo -e "${GREEN}Success! ${APP_NAME} has been installed.${NC}"
echo -e "${BLUE}Opening ${APP_NAME}...${NC}"
open "$INSTALL_DIR/$APP_NAME.app"
