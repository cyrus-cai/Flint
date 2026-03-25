#!/bin/bash
set -euo pipefail

REPO="${REPO:-cyrus-cai/Flint}"
APP_NAME="${APP_NAME:-Flint}"
ASSET_NAME="${ASSET_NAME:-$APP_NAME.zip}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
export RELEASE_CHANNEL="${RELEASE_CHANNEL:-stable}"
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

usage() {
    cat <<'EOF'
Usage: ./scripts/install.sh [--beta|--stable]
EOF
}

AUTH_HEADER=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
    AUTH_HEADER=(-H "Authorization: token $GITHUB_TOKEN")
fi

resolve_release_asset() {
    curl -fsSL "${AUTH_HEADER[@]}" "https://api.github.com/repos/$REPO/releases?per_page=50" |
        jq -r --arg asset "$ASSET_NAME" '
            [
                .[]
                | select(.draft == false)
                | select(
                    if env.RELEASE_CHANNEL == "beta" then
                        (.tag_name | contains("-beta"))
                    else
                        (.tag_name | contains("-beta") | not)
                    end
                )
                | {
                    tag: .tag_name,
                    url: (
                        .assets[]
                        | select(.name == $asset)
                        | .url
                    ),
                    browser_url: (
                        .assets[]
                        | select(.name == $asset)
                        | .browser_download_url
                    )
                }
                | select(.url != null)
            ][0]
            | if . == null then empty else "\(.tag)\t\(.url)\t\(.browser_url)" end
        '
}

while [ $# -gt 0 ]; do
    case "$1" in
        --beta)
            RELEASE_CHANNEL="beta"
            shift
            ;;
        --stable)
            RELEASE_CHANNEL="stable"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

echo "==> Resolving $RELEASE_CHANNEL release for $REPO"
RELEASE_INFO="$(resolve_release_asset)"
RELEASE_TAG="$(printf '%s\n' "$RELEASE_INFO" | awk -F '\t' 'NR == 1 { print $1 }')"
API_URL="$(printf '%s\n' "$RELEASE_INFO" | awk -F '\t' 'NR == 1 { print $2 }')"
BROWSER_URL="$(printf '%s\n' "$RELEASE_INFO" | awk -F '\t' 'NR == 1 { print $3 }')"

if [ -z "$API_URL" ] || [ "$API_URL" = "null" ]; then
    echo "Could not find asset $ASSET_NAME in the $RELEASE_CHANNEL GitHub Release feed." >&2
    exit 1
fi

echo "==> Downloading $APP_NAME from $RELEASE_TAG"
if [ -n "${GITHUB_TOKEN:-}" ]; then
    # Private repo: download via API with Accept header for binary
    curl -fL "${AUTH_HEADER[@]}" -H "Accept: application/octet-stream" "$API_URL" -o "$TEMP_DIR/$ASSET_NAME"
else
    # Public repo: browser_download_url works directly
    curl -fL "$BROWSER_URL" -o "$TEMP_DIR/$ASSET_NAME"
fi

echo "==> Installing to $INSTALL_DIR"
ditto -x -k "$TEMP_DIR/$ASSET_NAME" "$TEMP_DIR/extracted"

EXTRACTED_APP_PATH="$TEMP_DIR/extracted/$APP_NAME.app"
STAGED_APP_PATH="$INSTALL_DIR/$APP_NAME.app.new"
TARGET_APP_PATH="$INSTALL_DIR/$APP_NAME.app"

if [ ! -d "$EXTRACTED_APP_PATH" ]; then
    echo "Extracted app bundle not found: $EXTRACTED_APP_PATH" >&2
    exit 1
fi

rm -rf "$STAGED_APP_PATH"
cp -R "$EXTRACTED_APP_PATH" "$STAGED_APP_PATH"

if [ ! -d "$STAGED_APP_PATH" ]; then
    echo "Failed to stage app bundle at: $STAGED_APP_PATH" >&2
    exit 1
fi

if [ -d "$TARGET_APP_PATH" ]; then
    echo "==> Replacing existing installation"
    rm -rf "$TARGET_APP_PATH"
fi

mv "$STAGED_APP_PATH" "$TARGET_APP_PATH"

CLI_PATH="$TARGET_APP_PATH/Contents/Resources/flint-cli"
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
