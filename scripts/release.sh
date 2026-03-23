#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="${APP_NAME:-Flint}"
PLIST_PATH="${PLIST_PATH:-Flint-Info.plist}"
TAG_PREFIX="${TAG_PREFIX:-v}"
DEFAULT_PUBLISH_CODESIGN_IDENTITY="Developer ID Application"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
RELEASE_CHANNEL="${RELEASE_CHANNEL:-beta}"
TAG_SUFFIX="${TAG_SUFFIX:-}"
NOTES_FILE=""
SKIP_NOTARIZE=-1
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

RELEASE_SUPPORT_FILES=(
    "scripts/package.sh"
    "scripts/release.sh"
    "scripts/install.sh"
    "scripts/publish.sh"
    "README.md"
    "docs/release.md"
)

RESUME_ALLOWED_FILES=(
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
  --beta                   Create a GitHub beta release (default)
  --publish                Create a notarized production release
  --notes-file <path>      Use a notes file instead of --generate-notes
  --tag-suffix <suffix>    Override the generated tag suffix (beta defaults to -beta)
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

current_build_number() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST_PATH"
}

signing_identity_exists() {
    local identity="$1"

    if [ -z "$identity" ]; then
        return 1
    fi

    security find-identity -v -p codesigning | grep -F "$identity" >/dev/null 2>&1
}

is_release_managed_file() {
    local candidate="$1"
    local file

    for file in "${RESUME_ALLOWED_FILES[@]}"; do
        if [ "$candidate" = "$file" ]; then
            return 0
        fi
    done

    for file in "${RELEASE_SUPPORT_FILES[@]}"; do
        if [ "$candidate" = "$file" ]; then
            return 0
        fi
    done

    return 1
}

configure_release_mode() {
    case "$RELEASE_CHANNEL" in
        beta|publish)
            ;;
        *)
            echo "Unsupported release channel: $RELEASE_CHANNEL" >&2
            exit 1
            ;;
    esac

    if [ -z "$TAG_SUFFIX" ]; then
        if [ "$RELEASE_CHANNEL" = "beta" ]; then
            TAG_SUFFIX="-beta"
        fi
    fi

    if [ "$SKIP_NOTARIZE" = "-1" ]; then
        if [ "$RELEASE_CHANNEL" = "beta" ]; then
            SKIP_NOTARIZE=1
        else
            SKIP_NOTARIZE=0
        fi
    fi

    if [ "$RELEASE_CHANNEL" = "publish" ]; then
        if [ -z "$CODESIGN_IDENTITY" ]; then
            CODESIGN_IDENTITY="$DEFAULT_PUBLISH_CODESIGN_IDENTITY"
        fi
    elif [ -n "$CODESIGN_IDENTITY" ] && ! signing_identity_exists "$CODESIGN_IDENTITY"; then
        echo "==> Beta mode: signing identity not found, packaging without codesign"
        CODESIGN_IDENTITY=""
    fi

    export CODESIGN_IDENTITY
}

ensure_releasable_worktree() {
    local target_version="$1"
    local status_output
    status_output="$(git status --porcelain)"

    if [ -z "$status_output" ]; then
        return
    fi

    local path
    while IFS= read -r line; do
        path="${line:3}"

        if ! is_release_managed_file "$path"; then
            echo "Working tree is not clean. Commit or stash changes before releasing." >&2
            exit 1
        fi
    done <<< "$status_output"

    if [ "$(current_version)" = "$target_version" ]; then
        echo "==> Resuming interrupted release for version $target_version"
        return
    fi

    echo "Working tree is not clean. Commit or stash changes before releasing." >&2
    exit 1
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
        echo "==> Version already set to $version"
        return
    fi

    echo "==> Bumping version $current -> $version"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$PLIST_PATH"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1" "$PLIST_PATH"

    sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = $version;/g" Flint.xcodeproj/project.pbxproj
    sed -i '' "s/CURRENT_PROJECT_VERSION = .*;/CURRENT_PROJECT_VERSION = 1;/g" Flint.xcodeproj/project.pbxproj
    sed -i '' "s/return \".*\"/return \"$version\"/" FlintCLI/CLIVersion.swift
    sed -i '' "s/\"version\": \".*\"/\"version\": \"$version\"/" FlintMCP/package.json
    sed -i '' "s/const SERVER_VERSION = \".*\";/const SERVER_VERSION = \"$version\";/" FlintMCP/src/server.ts
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

verify_app_bundle() {
    local app_path="build/Export/$APP_NAME.app"

    if [ ! -d "$app_path" ]; then
        echo "Missing app bundle: $app_path" >&2
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

create_release_zip() {
    echo "==> Creating release zip"
    rm -f "build/$APP_NAME.zip"
    ditto -c -k --keepParent "build/Export/$APP_NAME.app" "build/$APP_NAME.zip"
}

create_release_dmg() {
    echo "==> Creating release DMG"
    rm -rf "build/DMG"
    mkdir -p "build/DMG"
    cp -R "build/Export/$APP_NAME.app" "build/DMG/"
    ln -s /Applications "build/DMG/Applications"

    rm -f "build/$APP_NAME.dmg"
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "build/DMG" \
        -ov \
        -format UDZO \
        "build/$APP_NAME.dmg"

    if [ -n "$CODESIGN_IDENTITY" ]; then
        codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "build/$APP_NAME.dmg"
        codesign --verify --verbose=2 "build/$APP_NAME.dmg"
    fi
}

commit_and_tag() {
    local version="$1"
    local tag="$2"
    local staged_files=("${VERSION_FILES[@]}")
    local file

    for file in "${RELEASE_SUPPORT_FILES[@]}"; do
        if ! git diff --quiet -- "$file"; then
            staged_files+=("$file")
        fi
    done

    echo "==> Creating release commit"
    git add "${staged_files[@]}"
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

normalize_github_release_flags() {
    local repo="$1"
    local tag="$2"
    local release_id=""

    release_id="$(gh api "repos/$repo/releases/tags/$tag" --jq '.id')"
    gh api \
        --method PATCH \
        "repos/$repo/releases/$release_id" \
        -F prerelease=false \
        >/dev/null
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
        normalize_github_release_flags "$repo" "$tag"
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
    normalize_github_release_flags "$repo" "$tag"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --beta)
            RELEASE_CHANNEL="beta"
            shift
            ;;
        --publish)
            RELEASE_CHANNEL="publish"
            shift
            ;;
        --notes-file)
            if [ $# -lt 2 ]; then
                echo "--notes-file requires a file path." >&2
                exit 1
            fi
            NOTES_FILE="$2"
            shift 2
            ;;
        --tag-suffix)
            if [ $# -lt 2 ]; then
                echo "--tag-suffix requires a suffix." >&2
                exit 1
            fi
            TAG_SUFFIX="$2"
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

load_env
require_command git
require_command security
require_command xcrun
require_command xcodebuild
require_command codesign
require_command bun
require_command ditto
require_command hdiutil

if [ -z "$VERSION" ]; then
    usage >&2
    exit 1
fi

if [ -n "$NOTES_FILE" ] && [ ! -f "$NOTES_FILE" ]; then
    echo "Notes file not found: $NOTES_FILE" >&2
    exit 1
fi

configure_release_mode

if [ "$SKIP_PUSH" = "1" ] && [ "$SKIP_GITHUB_RELEASE" = "0" ]; then
    echo "Refusing to create a GitHub Release without pushing the tag first." >&2
    exit 1
fi

if [ "$RELEASE_CHANNEL" = "publish" ] && [ "$SKIP_NOTARIZE" = "1" ] && [ "$SKIP_GITHUB_RELEASE" = "0" ]; then
    echo "Refusing to publish production GitHub Releases with unnotarized assets." >&2
    exit 1
fi

VERSION="${VERSION#${TAG_PREFIX}}"
TAG="${TAG_PREFIX}${VERSION}${TAG_SUFFIX}"
REPO="$(parse_remote_repo)"

ensure_releasable_worktree "$VERSION"
ensure_tag_absent "$TAG"
update_versions "$VERSION"

echo "==> Building $RELEASE_CHANNEL artifacts"
if [ "$SKIP_NOTARIZE" = "0" ]; then
    CREATE_ZIP=0 CREATE_DMG=0 ./scripts/package.sh
    verify_app_bundle
    create_release_zip
else
    ./scripts/package.sh
    verify_artifacts
fi

if [ "$SKIP_NOTARIZE" = "0" ]; then
    submit_for_notarization "build/$APP_NAME.zip"
    staple_and_validate "build/Export/$APP_NAME.app"
    create_release_zip
    create_release_dmg
    submit_for_notarization "build/$APP_NAME.dmg"
    staple_and_validate "build/$APP_NAME.dmg"
    verify_artifacts
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
echo "Channel: $RELEASE_CHANNEL"
echo "Tag: $TAG"
echo "Repo: $REPO"
echo "Assets:"
echo "  build/$APP_NAME.zip"
echo "  build/$APP_NAME.dmg"
