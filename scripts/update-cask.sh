#!/bin/bash
# update-cask.sh — Update the Homebrew cask file in this repo
#
# Usage:
#   ./scripts/update-cask.sh <version> [--tag-suffix <suffix>]
#
# Examples:
#   ./scripts/update-cask.sh 0.9.30                 # defaults to -beta suffix
#   ./scripts/update-cask.sh 1.0.0 --tag-suffix ""  # no suffix (production)
#
# Updates homebrew/Casks/flint.rb with the new version and sha256.
# The cask file is committed as part of the release — no separate repo needed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REPO="cyrus-cai/Flint"
CASK_FILE="$REPO_ROOT/homebrew/Casks/flint.rb"
TAG_SUFFIX="-beta"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <version> [--tag-suffix <suffix>]" >&2
    exit 1
fi

VERSION="$1"
shift

while [ $# -gt 0 ]; do
    case "$1" in
        --tag-suffix)
            TAG_SUFFIX="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

TAG="v${VERSION}${TAG_SUFFIX}"
ZIP_URL="https://github.com/${REPO}/releases/download/${TAG}/Flint.zip"

echo "==> Fetching sha256 for ${TAG}..."
SHA256="$(curl -sL "$ZIP_URL" | shasum -a 256 | awk '{print $1}')"

if [ -z "$SHA256" ] || [ ${#SHA256} -ne 64 ]; then
    echo "Failed to compute sha256. Is the release ${TAG} published?" >&2
    exit 1
fi

echo "    sha256: ${SHA256}"

echo "==> Updating ${CASK_FILE}"
sed -i '' "s/version \".*\"/version \"${VERSION}\"/" "$CASK_FILE"
sed -i '' "s/sha256 \".*\"/sha256 \"${SHA256}\"/" "$CASK_FILE"

if [ -n "$TAG_SUFFIX" ]; then
    sed -i '' "s|/v#{version}[^/]*/|/v#{version}${TAG_SUFFIX}/|" "$CASK_FILE"
else
    sed -i '' "s|/v#{version}[^/]*/|/v#{version}/|" "$CASK_FILE"
fi

echo "==> Cask updated to ${VERSION}"
