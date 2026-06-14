// Snow — sparse slow drifting flakes in 3 parallax layers. Each flake
// is a small soft circle that gently sways as it falls. Background-only;
// text passes through.
//
// IS_DAY (baked by ghostty-shaders apply from Open-Meteo's is_day, 1.0 day /
// 0.0 night) dims the flakes at night. Snow stays relatively visible after
// dark (it reflects ambient light well), so the night factor is gentle.
// Guarded so the scene compiles stand-alone (day look).

#ifndef IS_DAY
#define IS_DAY 1.0
#endif

float snowHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Snowflake shape — a soft fuzzy dot. `sizeJitter` scales the flake
// (0.7–1.3) per call so individual flakes vary in apparent distance.
//
// PERF: the previous version added a 6-fold-symmetry spike via atan()+cos()
// per flake. atan is one of the costlier GPU intrinsics, and the spikes are
// imperceptible at this on-screen flake size — dropped for a plain radial
// dot, which reads identically.
float snowflake(vec2 lp, float sizeJitter) {
    float r = length(lp);
    float core = smoothstep(0.04 * sizeJitter, 0.01 * sizeJitter, r);
    float halo = smoothstep(0.08 * sizeJitter, 0.04 * sizeJitter, r) * 0.22;
    return core + halo;
}

float snowLayer(vec2 uv, float speed, float density, float scale, float seed) {
    vec2 q = uv * scale + seed;
    // Bounded iTime + correct sign so flakes fall DOWN — see rain.glsl
    // for the full sign derivation.
    q.y += mod(iTime, 100.0) * speed;

    // PERF: hash the cell ONCE and early-out on density before doing any of
    // the per-flake work. The previous version hashed twice (once for the
    // sway phase, again after re-quantizing the swayed position) and ran the
    // sway sin() for every pixel — ~3 transcendentals per layer per pixel,
    // ×3 layers, all before the ~95% of cells that hold no flake bailed out.
    // Hashing once and gating first moves the sway sin behind the early-out,
    // so empty cells cost a single hash.
    vec2 cell = floor(q);
    float h = snowHash(cell);
    if (h < 1.0 - density) return 0.0;

    // Per-flake sway applied to the in-cell coordinate (not by re-quantizing
    // the cell). swayPhase from the cell hash keeps each flake decorrelated,
    // avoiding the in-phase diagonal waves the naive version produced.
    vec2 f = fract(q);
    float swayPhase = h * 6.28318;
    f.x += sin(q.y * 0.4 + swayPhase) * 0.25;

    // Per-flake size jitter (0.7–1.3) so flakes appear at varying apparent
    // distances. No rotation; real flakes at this distance don't visibly
    // spin and rotation drew the eye to them as flickering points.
    vec2 center = vec2(fract(h * 17.3), fract(h * 31.7));
    float sizeJitter = mix(0.7, 1.3, fract(h * 53.1));
    return snowflake(f - center, sizeJitter);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;

    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // 3 parallax layers: dim/far, mid, near/bright.
    float s = 0.0;
    s += snowLayer(uv, 0.4, 0.04, 12.0, 0.0) * 0.4;  // far
    s += snowLayer(uv, 0.6, 0.05, 18.0, 3.7) * 0.6;  // mid
    s += snowLayer(uv, 0.9, 0.06, 24.0, 7.3) * 0.8;  // near

    // Soft white — slight blue tint so it reads as cold/snowy.
    vec3 snowColor = vec3(0.68, 0.74, 0.82);
    // Night dimming: gentle — snow reflects ambient light and stays the most
    // visible of the precip scenes after dark. 1.0 by day, 0.65 at night.
    float dayDim = mix(0.65, 1.0, IS_DAY);
    vec3 effect = snowColor * s * 0.55 * dayDim;

    vec3 bgFinal = iBackgroundColor + effect;
    vec3 outRgb = bgFinal * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
