#!/usr/bin/env bash
# golden.sh — golden-image visual-regression harness for ghostty-weather scenes.
#
# Renders each of the 6 scenes to a deterministic single-frame PNG (fixed iTime,
# fixed small resolution, empty glyph layer) via the headless glsl_image harness,
# and either records those PNGs as references (`update`) or compares the current
# render against the committed references (`check`, the default).
#
# Subcommands:
#   golden.sh update   render all scenes → bench/golden/<scene>.png (overwrite)
#   golden.sh check    compare all scenes against bench/golden/<scene>.png,
#                      fail if any drifts beyond the tolerance (default)
#
# Env:
#   GHOSTTY_WEATHER_GOLDEN_TOLERANCE   mean abs per-channel RGB diff allowed,
#                                       0-255 scale (default 2.0)
#   GHOSTTY_WEATHER_GOLDEN_W / _H      render resolution (default 480 x 310)
#
# CROSS-HARDWARE CAVEAT
#   GPU floating-point is not bit-identical across vendors/drivers/OS versions,
#   so a reference generated on one machine can drift slightly on another even
#   with no shader change. The committed references in bench/golden/ are from the
#   maintainer's machine (Apple Silicon / macOS OpenGL); the tolerance is set
#   generous-but-meaningful to absorb that minor drift while still catching real
#   regressions (a changed effect moves the score far past it). If a *different*
#   runner legitimately exceeds tolerance with an unchanged shader, regenerate
#   the references on that environment with `golden.sh update` and commit them.
#
# macOS only (uses CGL/OpenGL via glsl_image). On non-Darwin hosts this is a
# clean no-op so CI lint lanes and Linux contributors do not fail.

set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SCENES_DIR="$SCRIPT_DIR/../shaders/scenes"
VENDOR_DIR="$SCRIPT_DIR/vendor"
GOLDEN_DIR="$SCRIPT_DIR/golden"
BIN="$SCRIPT_DIR/glsl_image"
SRC="$SCRIPT_DIR/glsl_image.c"

TOLERANCE="${GHOSTTY_WEATHER_GOLDEN_TOLERANCE:-2.0}"
W="${GHOSTTY_WEATHER_GOLDEN_W:-480}"
H="${GHOSTTY_WEATHER_GOLDEN_H:-310}"

CMD="${1:-check}"
case "$CMD" in
    check|update) ;;
    *) echo "golden.sh: unknown subcommand: $CMD (use 'check' or 'update')" >&2; exit 2 ;;
esac

if [[ "$(uname)" != "Darwin" ]]; then
    echo "golden.sh: golden-image render requires macOS/CGL; skipping."
    exit 0
fi

# --- Pinned stb single-header dependencies ----------------------------------
STB_COMMIT="5c205738c191bcb0abc65c4febfa9bd25ff35234"
STB_BASE="https://raw.githubusercontent.com/nothings/stb/${STB_COMMIT}"

fetch_stb() {
    local name="$1" guard="$2"
    local dest="$VENDOR_DIR/$name"
    [[ -s "$dest" ]] && grep -q "$guard" "$dest" && return 0
    mkdir -p "$VENDOR_DIR"
    echo "fetching $name (stb @ ${STB_COMMIT:0:10})..." >&2
    if ! curl -fsSL "$STB_BASE/$name" -o "$dest"; then
        echo "golden.sh: failed to download $name from $STB_BASE/$name" >&2
        rm -f "$dest"
        exit 1
    fi
    if [[ ! -s "$dest" ]] || ! grep -q "$guard" "$dest"; then
        echo "golden.sh: downloaded $name is empty or missing guard '$guard'" >&2
        rm -f "$dest"
        exit 1
    fi
}

fetch_stb "stb_image.h"       "STBI_INCLUDE_STB_IMAGE_H"
fetch_stb "stb_image_write.h" "INCLUDE_STB_IMAGE_WRITE_H"

# --- Build glsl_image if missing or stale -----------------------------------
if [[ ! -x "$BIN" || "$SRC" -nt "$BIN" \
      || "$VENDOR_DIR/stb_image.h" -nt "$BIN" \
      || "$VENDOR_DIR/stb_image_write.h" -nt "$BIN" ]]; then
    echo "building glsl_image..." >&2
    clang -O2 -DGL_SILENCE_DEPRECATION "$SRC" -framework OpenGL -o "$BIN"
fi

SCENES=$(find "$SCENES_DIR" -maxdepth 1 -name '*.glsl' -exec basename {} .glsl \; | sort)

# --- update: (re)generate references ----------------------------------------
if [[ "$CMD" == "update" ]]; then
    mkdir -p "$GOLDEN_DIR"
    echo "rendering golden references at ${W}x${H} -> $GOLDEN_DIR"
    while IFS= read -r s; do
        [[ -n "$s" ]] || continue
        "$BIN" "$SCENES_DIR/$s.glsl" --write "$GOLDEN_DIR/$s.png" "$W" "$H" >/dev/null
        echo "  wrote $s.png"
    done <<< "$SCENES"
    echo "done. Commit bench/golden/*.png."
    exit 0
fi

# --- check: compare each scene against its reference ------------------------
echo "golden-image check (tolerance ${TOLERANCE}, mean abs RGB diff 0-255)"
fail=0
missing=0
while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    ref="$GOLDEN_DIR/$s.png"
    if [[ ! -f "$ref" ]]; then
        printf "  %-14s MISSING reference (%s)\n" "$s" "$ref"
        missing=$((missing + 1))
        continue
    fi
    out=$("$BIN" "$SCENES_DIR/$s.glsl" --compare "$ref" --tolerance "$TOLERANCE" 2>/dev/null) && verdict="ok" || verdict="DRIFT"
    score=$(printf '%s\n' "$out" | sed -n 's/.*meanabsdiff=\([0-9.]*\).*/\1/p')
    printf "  %-14s score=%-10s %s\n" "$s" "${score:-?}" "$verdict"
    [[ "$verdict" == "ok" ]] || fail=$((fail + 1))
done <<< "$SCENES"

echo
if [[ "$missing" -gt 0 ]]; then
    echo "RESULT: $missing reference(s) missing — run 'golden.sh update' to create them." >&2
    exit 1
fi
if [[ "$fail" -gt 0 ]]; then
    echo "RESULT: $fail scene(s) drifted beyond tolerance ${TOLERANCE}." >&2
    exit 1
fi
echo "RESULT: all scenes within golden tolerance ${TOLERANCE}."
