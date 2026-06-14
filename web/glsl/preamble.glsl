#version 300 es
// WebGL2 (GLSL ES 3.00) preamble for ghostty-shaders scenes — the web
// gallery's equivalent of the preamble Ghostty injects at runtime. It
// declares exactly the four uniforms Ghostty supplies and nothing else.
//
// Consumed by BOTH web/gallery.js (at runtime, in the browser) and
// bench/wrap-shader.sh --profile es300 (in CI, via glslangValidator), so
// CI validates the same preamble/epilogue text the browser compiles. The
// browser additionally bakes #defines between preamble and scene; CI
// covers that variant too (wrap-shader.sh --defines).
precision highp float;
precision highp int;
uniform vec3  iResolution;
uniform float iTime;
uniform sampler2D iChannel0;
uniform vec3  iBackgroundColor;
out vec4 _ghostty_fragColor;
