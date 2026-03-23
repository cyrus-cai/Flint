#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="${APP_NAME:-Flint}"
SCHEME="${SCHEME:-Flint}"
PROJECT_PATH="${PROJECT_PATH:-Flint.xcodeproj}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="${BUILD_DIR:-build}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$BUILD_DIR/$APP_NAME.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$BUILD_DIR/Export}"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
ZIP_PATH="${ZIP_PATH:-$BUILD_DIR/$APP_NAME.zip}"
DMG_PATH="${DMG_PATH:-$BUILD_DIR/$APP_NAME.dmg}"
DMG_STAGING_PATH="${DMG_STAGING_PATH:-$BUILD_DIR/DMG}"
PLIST_PATH="${PLIST_PATH:-Flint-Info.plist}"
MCP_DIR="${MCP_DIR:-FlintMCP}"
MCP_ENTRYPOINT="${MCP_ENTRYPOINT:-$MCP_DIR/dist/server.mjs}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY-Developer ID Application}"
CODESIGN_ENTITLEMENTS="${CODESIGN_ENTITLEMENTS:-}"
CREATE_ZIP="${CREATE_ZIP:-1}"
CREATE_DMG="${CREATE_DMG:-1}"
CLEAN_BUILD="${CLEAN_BUILD:-1}"

BUILD_SETTINGS=""

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

read_plist_value() {
    local key="$1"
    /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST_PATH" 2>/dev/null || true
}

build_setting() {
    local key="$1"
    echo "$BUILD_SETTINGS" | awk -F ' = ' -v key="$key" '$1 ~ "^[[:space:]]*" key "$" { print $2; exit }'
}

load_build_settings() {
    BUILD_SETTINGS="$(
        xcodebuild -project "$PROJECT_PATH" \
            -scheme "$SCHEME" \
            -configuration "$CONFIGURATION" \
            -showBuildSettings 2>/dev/null
    )"
}

resolve_version_info() {
    MARKETING_VERSION="$(read_plist_value CFBundleShortVersionString)"
    CURRENT_PROJECT_VERSION="$(read_plist_value CFBundleVersion)"

    if [ -z "$MARKETING_VERSION" ]; then
        MARKETING_VERSION="$(build_setting MARKETING_VERSION)"
    fi

    if [ -z "$CURRENT_PROJECT_VERSION" ]; then
        CURRENT_PROJECT_VERSION="$(build_setting CURRENT_PROJECT_VERSION)"
    fi

    if [ -z "$MARKETING_VERSION" ]; then
        echo "Failed to resolve MARKETING_VERSION." >&2
        exit 1
    fi

    if [ -z "$CURRENT_PROJECT_VERSION" ]; then
        echo "Failed to resolve CURRENT_PROJECT_VERSION." >&2
        exit 1
    fi
}

archive_app() {
    echo "==> Archiving $APP_NAME $MARKETING_VERSION ($CURRENT_PROJECT_VERSION)"
    xcodebuild -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -archivePath "$ARCHIVE_PATH" \
        -destination 'generic/platform=macOS' \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        archive
}

copy_app_from_archive() {
    echo "==> Copying app from archive"
    mkdir -p "$EXPORT_PATH"
    rm -rf "$APP_PATH"
    cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$APP_PATH"

    if [ ! -d "$APP_PATH" ]; then
        echo "Archived app not found at $APP_PATH" >&2
        exit 1
    fi
}

require_signing_identity() {
    if [ -z "$CODESIGN_IDENTITY" ]; then
        return
    fi

    if ! security find-identity -v -p codesigning | grep -F "$CODESIGN_IDENTITY" >/dev/null 2>&1; then
        echo "Signing identity not found: $CODESIGN_IDENTITY" >&2
        echo "Install a Developer ID Application certificate into your keychain, or set CODESIGN_IDENTITY to a valid identity." >&2
        exit 1
    fi
}

build_mcp() {
    echo "==> Building FlintMCP"
    if [ ! -d "$MCP_DIR" ]; then
        echo "FlintMCP directory not found at $MCP_DIR" >&2
        exit 1
    fi

    require_command bun

    if [ ! -f "$MCP_DIR/bun.lock" ] && [ ! -f "$MCP_DIR/bun.lockb" ]; then
        echo "Missing FlintMCP Bun lockfile." >&2
        exit 1
    fi

    (
        cd "$MCP_DIR"
        if [ -d node_modules ]; then
            echo "==> Reusing existing FlintMCP dependencies"
        else
            bun install --frozen-lockfile
        fi
        bun run build
    )

    if [ ! -f "$MCP_ENTRYPOINT" ]; then
        echo "Built FlintMCP entrypoint not found at $MCP_ENTRYPOINT" >&2
        exit 1
    fi
}

embed_mcp() {
    local destination="$APP_PATH/Contents/Resources/FlintMCP"

    echo "==> Embedding FlintMCP"
    rm -rf "$destination"
    mkdir -p "$destination"
    cp "$MCP_ENTRYPOINT" "$destination/server.mjs"
    chmod 755 "$destination/server.mjs"
}

resign_app() {
    if [ -z "$CODESIGN_IDENTITY" ]; then
        echo "==> Skipping codesign (CODESIGN_IDENTITY is empty)"
        return
    fi

    echo "==> Re-signing app with $CODESIGN_IDENTITY"
    xattr -cr "$APP_PATH"

    local codesign_args=(
        --force
        --deep
        --timestamp
        --options runtime
        --sign "$CODESIGN_IDENTITY"
    )

    if [ -n "$CODESIGN_ENTITLEMENTS" ]; then
        if [ ! -f "$CODESIGN_ENTITLEMENTS" ]; then
            echo "CODESIGN_ENTITLEMENTS file not found: $CODESIGN_ENTITLEMENTS" >&2
            exit 1
        fi
        codesign_args+=(--entitlements "$CODESIGN_ENTITLEMENTS")
    fi

    codesign "${codesign_args[@]}" "$APP_PATH"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
}

create_zip() {
    if [ "$CREATE_ZIP" != "1" ]; then
        return
    fi

    echo "==> Creating zip archive"
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
}

create_dmg() {
    if [ "$CREATE_DMG" != "1" ]; then
        return
    fi

    echo "==> Creating DMG"
    rm -rf "$DMG_STAGING_PATH"
    mkdir -p "$DMG_STAGING_PATH"
    cp -R "$APP_PATH" "$DMG_STAGING_PATH/"
    ln -s /Applications "$DMG_STAGING_PATH/Applications"

    rm -f "$DMG_PATH"
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$DMG_STAGING_PATH" \
        -ov \
        -format UDZO \
        "$DMG_PATH"

    if [ -n "$CODESIGN_IDENTITY" ]; then
        codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
        codesign --verify --verbose=2 "$DMG_PATH"
    fi
}

print_summary() {
    echo "==> Package ready"
    echo "Version: $MARKETING_VERSION ($CURRENT_PROJECT_VERSION)"
    echo "App: $APP_PATH"

    if [ -f "$ZIP_PATH" ]; then
        echo "Zip: $ZIP_PATH"
    fi

    if [ -f "$DMG_PATH" ]; then
        echo "DMG: $DMG_PATH"
    fi
}

main() {
    require_command xcodebuild
    require_command codesign
    require_command ditto
    require_command hdiutil
    require_command security
    require_command xattr

    load_build_settings
    resolve_version_info
    require_signing_identity

    if [ "$CLEAN_BUILD" = "1" ]; then
        echo "==> Cleaning build directory"
        rm -rf "$BUILD_DIR"
    fi

    mkdir -p "$BUILD_DIR"
    archive_app
    copy_app_from_archive
    build_mcp
    embed_mcp
    resign_app
    create_zip
    create_dmg
    print_summary
}

main "$@"
