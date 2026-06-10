#!/usr/bin/env bash
# build-site.sh — assemble the static WebGL2 gallery into <outdir>.
#
# There is no bundler and nothing to compile; "build" is laying files out in
# the shape the gallery fetches at runtime (and GitHub Pages serves):
#
#   web/*             -> <outdir>/          page, JS, CSS, glsl/ wrapping
#   shaders/scenes/*  -> <outdir>/scenes/   the EXACT scene sources Ghostty runs
#
# Used by .github/workflows/pages.yml for deploys and scripts/serve-site.sh
# for local preview, so local preview and production are the same layout.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="${1:-_site}"

mkdir -p "$OUT/scenes"
cp -R "$REPO_ROOT/web/." "$OUT/"
cp "$REPO_ROOT"/shaders/scenes/*.glsl "$OUT/scenes/"

echo "site assembled at $OUT" >&2
