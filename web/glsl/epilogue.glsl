// Web epilogue: drive Shadertoy-style mainImage() from a real main().
//
// Ghostty hands scenes a TOP-origin fragCoord (Metal convention, y=0 at
// the top) and every scene flips uv.y once on that assumption. OpenGL's
// gl_FragCoord is BOTTOM-origin, so present the scene with Ghostty's
// convention by flipping here — otherwise every sky renders upside down.
// (The gl410 bench profile leaves the coordinate unflipped; the image
// harness compensates by reading rows back bottom-first, which already
// yields scene-upright PNGs — see glsl_image.c render_frame.)
//
// GW_SS is the configurable compute<->clarity dial: GW_SS×GW_SS supersamples
// per pixel (centered sub-positions, averaged) for anti-aliasing. GW_SS=1
// (default) is exactly the original single-sample behaviour; higher values
// cost ~GW_SS² more GPU but render thin features / moving highlights crisper.
#ifndef GW_SS
#define GW_SS 1
#endif

void main() {
    vec2 base = vec2(gl_FragCoord.x, iResolution.y - gl_FragCoord.y);
    vec4 acc = vec4(0.0);
    for (int sy = 0; sy < GW_SS; sy++) {
        for (int sx = 0; sx < GW_SS; sx++) {
            // centered sub-pixel offset within this pixel
            vec2 off = (vec2(float(sx), float(sy)) + 0.5) / float(GW_SS) - 0.5;
            vec4 c;
            mainImage(c, base + vec2(off.x, -off.y));
            acc += c;
        }
    }
    _ghostty_fragColor = acc / float(GW_SS * GW_SS);
}
