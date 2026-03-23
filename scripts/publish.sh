#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "scripts/publish.sh is deprecated. Use scripts/release.sh instead." >&2
exec ./scripts/release.sh "$@"
