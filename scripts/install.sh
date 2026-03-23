#!/bin/bash
set -euo pipefail

REPO="${REPO:-cyrus-cai/Flint}"
APP_NAME="${APP_NAME:-Flint}"
ASSET_NAME="${ASSET_NAME:-$APP_NAME.zip}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
TEMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

require_command curl
require_command jq
require_command ditto

echo "==> Resolving latest release for $REPO"
LATEST_URL="$(
    curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" |
        jq -r --arg asset "$ASSET_NAME" '.assets[] | select(.name == $asset) | .browser_download_url' |
        head -n 1
)"

if [ -z "$LATEST_URL" ] || [ "$LATEST_URL" = "null" ]; then
    echo "Could not find asset $ASSET_NAME in the latest GitHub Release." >&2
    exit 1
fi

echo "==> Downloading $APP_NAME"
curl -fL "$LATEST_URL" -o "$TEMP_DIR/$ASSET_NAME"

echo "==> Installing to $INSTALL_DIR"
ditto -x -k "$TEMP_DIR/$ASSET_NAME" "$TEMP_DIR/extracted"

if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo "==> Replacing existing installation"
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi

mv "$TEMP_DIR/extracted/$APP_NAME.app" "$INSTALL_DIR/"

CLI_PATH="$INSTALL_DIR/$APP_NAME.app/Contents/Resources/flint-cli"
if [ -f "$CLI_PATH" ]; then
    for BIN_DIR in "$HOME/.local/bin" "/usr/local/bin"; do
        LINK_PATH="$BIN_DIR/flint"
        mkdir -p "$BIN_DIR" 2>/dev/null || continue

        if [ -e "$LINK_PATH" ] && [ ! -L "$LINK_PATH" ]; then
            echo "Skipping $LINK_PATH because it already exists and is not a symlink." >&2
            continue
        fi

        if ln -sfn "$CLI_PATH" "$LINK_PATH" 2>/dev/null; then
            echo "==> Installed CLI symlink: $LINK_PATH"
            break
        fi
    done
fi

echo "==> Install complete"
