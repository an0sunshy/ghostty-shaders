// Web epilogue: drive Shadertoy-style mainImage() from a real main().
//
// Ghostty hands scenes a TOP-origin fragCoord (Metal convention, y=0 at
// the top) and every scene flips uv.y once on that assumption. OpenGL's
// gl_FragCoord is BOTTOM-origin, so present the scene with Ghostty's
// convention by flipping here — otherwise every sky renders upside down.
// (The gl410 bench profile does NOT flip; the headless harness flips at
// PNG write-out instead.)
void main() {
    vec4 c;
    mainImage(c, vec2(gl_FragCoord.x, iResolution.y - gl_FragCoord.y));
    _ghostty_fragColor = c;
}
