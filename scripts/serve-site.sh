#!/usr/bin/env bash
# serve-site.sh — build the gallery into a temp dir and serve it locally,
# mirroring exactly what GitHub Pages deploys.
#
#   scripts/serve-site.sh [port]    # default port 8642

set -euo pipefail

PORT="${1:-8642}"
REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"

SITE="$(mktemp -d "${TMPDIR:-/tmp}/ghostty-shaders-site.XXXXXX")"
trap 'rm -rf "$SITE"' EXIT

"$REPO_ROOT/scripts/build-site.sh" "$SITE"

echo "serving http://localhost:$PORT/ (ctrl-c to stop)" >&2
python3 -m http.server "$PORT" --directory "$SITE"
