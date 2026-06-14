#!/usr/bin/env bash
# build-site.sh — assemble the static WebGL2 gallery into <outdir>.
#
# There is no bundler and nothing to compile; "build" is laying files out in
# the shape the gallery fetches at runtime (and GitHub Pages serves):
#
#   web/*             -> <outdir>/          page, JS, CSS, glsl/ wrapping
#   shaders/**/*.glsl -> <outdir>/scenes/   the EXACT scene sources Ghostty runs
#                                           (flattened — scene names are unique)
#
# Used by .github/workflows/pages.yml for deploys and scripts/serve-site.sh
# for local preview, so local preview and production are the same layout.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="${1:-_site}"

# shellcheck source=scene-discovery.sh disable=SC1091
. "$REPO_ROOT/scripts/scene-discovery.sh"

mkdir -p "$OUT/scenes"
cp -R "$REPO_ROOT/web/." "$OUT/"
# Flatten every collection into _site/scenes/ — names are globally unique, and
# the gallery fetches scenes/<name>.glsl regardless of source category.
while IFS= read -r f; do
    cp "$f" "$OUT/scenes/"
done < <(scene_files "$REPO_ROOT/shaders")

echo "site assembled at $OUT" >&2
