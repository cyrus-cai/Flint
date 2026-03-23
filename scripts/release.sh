#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="${APP_NAME:-Flint}"
PLIST_PATH="${PLIST_PATH:-Flint-Info.plist}"
TAG_PREFIX="${TAG_PREFIX:-v}"
NOTES_FILE=""
SKIP_NOTARIZE=0
SKIP_PUSH=0
SKIP_GITHUB_RELEASE=0
VERSION=""

VERSION_FILES=(
    "Flint-Info.plist"
    "Flint.xcodeproj/project.pbxproj"
    "FlintCLI/CLIVersion.swift"
    "FlintMCP/package.json"
    "FlintMCP/src/server.ts"
)

usage() {
    cat <<'EOF'
Usage: ./scripts/release.sh <version> [options]

Options:
  --notes-file <path>      Use a notes file instead of --generate-notes
  --skip-notarize          Build assets but skip notarization and stapling
  --skip-push              Do not push the release commit and tag
  --skip-github-release    Do not create or update the GitHub Release
EOF
}

load_env() {
    if [ -f .env ]; then
        set -a
        # shellcheck disable=SC1091
        source .env
        set +a
    fi
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

build_setting() {
    local key="$1"
    xcodebuild -project Flint.xcodeproj -scheme Flint -showBuildSettings 2>/dev/null |
        awk -F ' = ' -v key="$key" '$1 ~ "^[[:space:]]*" key "$" { print $2; exit }'
}

current_version() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST_PATH"
}

ensure_clean_worktree() {
    if [ -n "$(git status --porcelain)" ]; then
        echo "Working tree is not clean. Commit or stash changes before releasing." >&2
        exit 1
    fi
}

parse_remote_repo() {
    local remote_url
    remote_url="$(git config --get remote.origin.url)"

    case "$remote_url" in
        git@github.com:*)
            remote_url="${remote_url#git@github.com:}"
            ;;
        https://github.com/*)
            remote_url="${remote_url#https://github.com/}"
            ;;
        *)
            echo "Unsupported GitHub remote URL: $remote_url" >&2
            exit 1
            ;;
    esac

    remote_url="${remote_url%.git}"
    echo "$remote_url"
}

ensure_tag_absent() {
    local tag="$1"

    if git rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
        echo "Tag already exists locally: $tag" >&2
        exit 1
    fi

    if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
        echo "Tag already exists on origin: $tag" >&2
        exit 1
    fi
}

update_versions() {
    local version="$1"
    local current
    current="$(current_version)"

    if [ "$version" = "$current" ]; then
        echo "Version $version is already set in $PLIST_PATH." >&2
        exit 1
    fi

    echo "==> Bumping version $current -> $version"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$PLIST_PATH"

    sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = $version;/g" Flint.xcodeproj/project.pbxproj
    sed -i '' "s/return \".*\"/return \"$version\"/" FlintCLI/CLIVersion.swift
    sed -i '' "s/\"version\": \".*\"/\"version\": \"$version\"/" FlintMCP/package.json
    sed -i '' "s/const SERVER_VERSION = \".*\";/const SERVER_VERSION = \"$version\";/" FlintMCP/src/server.ts

    echo "==> Resetting build number to 1"
    xcrun agvtool new-version -all 1
}

verify_artifacts() {
    local app_path="build/Export/$APP_NAME.app"
    local zip_path="build/$APP_NAME.zip"
    local dmg_path="build/$APP_NAME.dmg"

    if [ ! -d "$app_path" ]; then
        echo "Missing app bundle: $app_path" >&2
        exit 1
    fi

    if [ ! -f "$zip_path" ]; then
        echo "Missing zip archive: $zip_path" >&2
        exit 1
    fi

    if [ ! -f "$dmg_path" ]; then
        echo "Missing DMG: $dmg_path" >&2
        exit 1
    fi
}

notary_args() {
    local profile="${NOTARY_PROFILE:-${APPLE_NOTARY_PROFILE:-}}"
    local password="${APPLE_APP_PASSWORD:-${APPLE_APP_SPECIFIC_PASSWORD:-}}"
    local resolved_team_id="${TEAM_ID:-}"
    local team_id="${APPLE_TEAM_ID:-}"

    if [ -z "$resolved_team_id" ]; then
        resolved_team_id="$(build_setting DEVELOPMENT_TEAM)"
    fi

    if [ -z "$team_id" ]; then
        team_id="$resolved_team_id"
    fi

    if [ -n "$profile" ]; then
        echo "--keychain-profile"$'\n'"$profile"
        return
    fi

    if [ -n "${APPLE_ID:-}" ] && [ -n "$password" ] && [ -n "$team_id" ]; then
        echo "--apple-id"$'\n'"${APPLE_ID}"
        echo "--password"$'\n'"$password"
        echo "--team-id"$'\n'"$team_id"
        return
    fi

    echo "Missing notarization credentials. Set NOTARY_PROFILE or APPLE_ID / APPLE_APP_PASSWORD / APPLE_TEAM_ID." >&2
    exit 1
}

submit_for_notarization() {
    local artifact="$1"
    local args=()

    while IFS= read -r line; do
        args+=("$line")
    done < <(notary_args)

    echo "==> Notarizing $(basename "$artifact")"
    xcrun notarytool submit "$artifact" "${args[@]}" --wait
}

staple_and_validate() {
    local artifact="$1"

    echo "==> Stapling $(basename "$artifact")"
    xcrun stapler staple "$artifact"
    xcrun stapler validate "$artifact"
}

commit_and_tag() {
    local version="$1"
    local tag="$2"

    echo "==> Creating release commit"
    git add "${VERSION_FILES[@]}"
    git commit -m "Release $tag"

    echo "==> Creating git tag $tag"
    git tag -a "$tag" -m "Release $tag"
}

push_refs() {
    local tag="$1"
    local branch
    branch="$(git rev-parse --abbrev-ref HEAD)"

    if [ "$branch" = "HEAD" ]; then
        echo "Detached HEAD is not supported for release pushes." >&2
        exit 1
    fi

    echo "==> Pushing branch $branch"
    git push origin "$branch"

    echo "==> Pushing tag $tag"
    git push origin "$tag"
}

publish_github_release() {
    local repo="$1"
    local tag="$2"
    local assets=("build/$APP_NAME.zip" "build/$APP_NAME.dmg")

    if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
        echo "==> Updating existing GitHub Release $tag"
        gh release upload "$tag" "${assets[@]}" --clobber --repo "$repo"
        if [ -n "$NOTES_FILE" ]; then
            gh release edit "$tag" --title "$tag" --notes-file "$NOTES_FILE" --repo "$repo"
        fi
        return
    fi

    echo "==> Creating GitHub Release $tag"
    if [ -n "$NOTES_FILE" ]; then
        gh release create "$tag" "${assets[@]}" \
            --repo "$repo" \
            --title "$tag" \
            --notes-file "$NOTES_FILE"
    else
        gh release create "$tag" "${assets[@]}" \
            --repo "$repo" \
            --title "$tag" \
            --generate-notes
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --notes-file)
            if [ $# -lt 2 ]; then
                echo "--notes-file requires a file path." >&2
                exit 1
            fi
            NOTES_FILE="$2"
            shift 2
            ;;
        --skip-notarize)
            SKIP_NOTARIZE=1
            shift
            ;;
        --skip-push)
            SKIP_PUSH=1
            shift
            ;;
        --skip-github-release)
            SKIP_GITHUB_RELEASE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            if [ -n "$VERSION" ]; then
                echo "Version may only be specified once." >&2
                exit 1
            fi
            VERSION="$1"
            shift
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    usage >&2
    exit 1
fi

if [ -n "$NOTES_FILE" ] && [ ! -f "$NOTES_FILE" ]; then
    echo "Notes file not found: $NOTES_FILE" >&2
    exit 1
fi

if [ "$SKIP_PUSH" = "1" ] && [ "$SKIP_GITHUB_RELEASE" = "0" ]; then
    echo "Refusing to create a GitHub Release without pushing the tag first." >&2
    exit 1
fi

if [ "$SKIP_NOTARIZE" = "1" ] && [ "$SKIP_GITHUB_RELEASE" = "0" ]; then
    echo "Refusing to publish GitHub Releases with unnotarized assets." >&2
    exit 1
fi

load_env
require_command git
require_command xcrun
require_command xcodebuild
require_command codesign
require_command bun
ensure_clean_worktree

VERSION="${VERSION#${TAG_PREFIX}}"
TAG="${TAG_PREFIX}${VERSION}"
REPO="$(parse_remote_repo)"

ensure_tag_absent "$TAG"
update_versions "$VERSION"

echo "==> Building release artifacts"
./scripts/package.sh
verify_artifacts

if [ "$SKIP_NOTARIZE" = "0" ]; then
    submit_for_notarization "build/$APP_NAME.zip"
    staple_and_validate "build/Export/$APP_NAME.app"
    submit_for_notarization "build/$APP_NAME.dmg"
    staple_and_validate "build/$APP_NAME.dmg"
fi

commit_and_tag "$VERSION" "$TAG"

if [ "$SKIP_PUSH" = "0" ]; then
    push_refs "$TAG"
fi

if [ "$SKIP_GITHUB_RELEASE" = "0" ]; then
    require_command gh
    gh auth status >/dev/null
    publish_github_release "$REPO" "$TAG"
fi

echo "==> Release complete"
echo "Tag: $TAG"
echo "Repo: $REPO"
echo "Assets:"
echo "  build/$APP_NAME.zip"
echo "  build/$APP_NAME.dmg"
