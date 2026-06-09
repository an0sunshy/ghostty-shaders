#!/usr/bin/env bash
# wrap-shader.sh — emit a complete, stand-alone GLSL fragment shader for a
# ghostty-weather scene, to stdout.
#
# It prints the EXACT same wrapping the headless harness (glsl_bench.c /
# glsl_image.c) uses: a "#version 410 core" preamble declaring the four Ghostty
# uniforms (iResolution, iTime, iChannel0, iBackgroundColor) and the output, the
# scene source verbatim, then an epilogue main() that drives Shadertoy's
# mainImage(). The result is a self-contained shader that a syntax checker such
# as glslangValidator (Linux CI) can validate without the C harness or a GPU:
#
#   bench/wrap-shader.sh shaders/scenes/cloudy.glsl | glslangValidator --stdin -S frag
#
# Pure text; fully cross-platform (no macOS/GL dependency). The preamble and
# epilogue are mirrored from glsl_bench.c PREAMBLE/EPILOGUE — keep them in sync
# if that wrapping ever changes.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <scene.glsl>" >&2
    exit 2
fi

SCENE="$1"
if [[ ! -f "$SCENE" ]]; then
    echo "wrap-shader.sh: no such file: $SCENE" >&2
    exit 1
fi

# Preamble — identical to glsl_bench.c PREAMBLE. The "#line 1" makes any
# compiler diagnostics report scene-relative line numbers.
cat <<'PREAMBLE'
#version 410 core
uniform vec3  iResolution;
uniform float iTime;
uniform sampler2D iChannel0;
uniform vec3  iBackgroundColor;
out vec4 _ghostty_fragColor;
#line 1
PREAMBLE

# Scene source verbatim.
cat "$SCENE"

# Epilogue — identical to glsl_bench.c EPILOGUE.
cat <<'EPILOGUE'

void main() {
    vec4 c;
    mainImage(c, gl_FragCoord.xy);
    _ghostty_fragColor = c;
}
EPILOGUE
