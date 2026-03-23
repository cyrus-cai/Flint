#!/bin/bash
set -euo pipefail

REPO="${REPO:-cyrus-cai/Flint}"
APP_NAME="${APP_NAME:-Flint}"
ASSET_NAME="${ASSET_NAME:-$APP_NAME.zip}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
RELEASE_CHANNEL="${RELEASE_CHANNEL:-stable}"
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

resolve_release_asset() {
    if [ "$RELEASE_CHANNEL" = "beta" ]; then
        curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=20" |
            jq -r --arg asset "$ASSET_NAME" '
                [
                    .[]
                    | select(.draft == false and .prerelease == true)
                    | {
                        tag: .tag_name,
                        url: (
                            .assets[]
                            | select(.name == $asset)
                            | .browser_download_url
                        )
                    }
                    | select(.url != null)
                ][0]
                | if . == null then empty else "\(.tag)\t\(.url)" end
            '
        return
    fi

    curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" |
        jq -r --arg asset "$ASSET_NAME" '
            if .tag_name == null then
                empty
            else
                [
                    .tag_name,
                    (
                        .assets[]
                        | select(.name == $asset)
                        | .browser_download_url
                    )
                ] | @tsv
            end
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
LATEST_URL="$(printf '%s\n' "$RELEASE_INFO" | awk -F '\t' 'NR == 1 { print $2 }')"

if [ -z "$LATEST_URL" ] || [ "$LATEST_URL" = "null" ]; then
    echo "Could not find asset $ASSET_NAME in the $RELEASE_CHANNEL GitHub Release feed." >&2
    exit 1
fi

echo "==> Downloading $APP_NAME from $RELEASE_TAG"
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
