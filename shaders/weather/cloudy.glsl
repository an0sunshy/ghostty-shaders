// Cloudy — slow drifting cloud puffs. fbm noise thresholded into distinct
// soft-edged blobs that scroll horizontally. Background-only; text passes
// through.
//
// Tuned subtle: clouds tint the bg toward light grey only inside the puffs,
// the rest stays the user's Nightfox bg.
//
// IS_DAY (baked by ghostty-shaders apply from Open-Meteo's is_day, 1.0 day /
// 0.0 night) dims the cloud lighting at night so an overcast night still
// reads as nighttime. Guarded so the scene compiles stand-alone (day look).

#ifndef IS_DAY
#define IS_DAY 1.0
#endif

float cloudHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float cloudNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);  // smoothstep interpolation
    float a = cloudHash(i);
    float b = cloudHash(i + vec2(1.0, 0.0));
    float c = cloudHash(i + vec2(0.0, 1.0));
    float d = cloudHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;

    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // Slow horizontal drift, bounded so iTime precision stays clean.
    // Slightly faster than before (0.012 → 0.018) — the previous pace
    // bordered on imperceptible.
    float t = mod(iTime, 1000.0) * 0.018;

    // Vertical density bias: cumulus thin out near the zenith and sit in the
    // upper-mid sky. Computed FIRST so the expensive fbm is skipped entirely
    // for fragments outside the band (top ~5% and bottom ~30% of the screen),
    // where the cloud contribution is zero regardless. PERF: gate, don't
    // compute-then-multiply-by-zero — the band fraction sets the scene's cost.
    float vbias = smoothstep(0.95, 0.55, uv.y) * smoothstep(0.30, 0.55, uv.y);

    vec3 effect = vec3(0.0);
    if (vbias > 0.0) {
        // Anisotropic sampling — clouds are wider than tall.
        vec2 cp = vec2(uv.x * 2.5 + t, (uv.y - 0.15) * 1.2);
        // 2-octave fbm inlined so both octaves can be reused for shading —
        // total cost is two cloudNoise samples (PERF: the whole scene's hot
        // path). norm 0.75 = 0.5 + 0.25 keeps density in [0,1) so the
        // threshold below stays stable.
        float n0 = cloudNoise(cp);
        float n1 = cloudNoise(cp * 2.0 + 7.3);
        float density = (0.5 * n0 + 0.25 * n1) / 0.75;
        // Smooth threshold so puffs have soft edges instead of crisp shapes.
        float cloud = smoothstep(0.42, 0.62, density) * vbias;

        // Two-tone shading from octave contrast: where the fine octave sits
        // above the coarse base the puff face catches light (bright top);
        // below it reads as a shaded underside. Reuses n0/n1 — no extra
        // samples — and still sells puff volume.
        float shade = smoothstep(-0.18, 0.18, n1 - n0);
        vec3 cloudColor = mix(vec3(0.22, 0.24, 0.28),  // shaded underside
                              vec3(0.36, 0.38, 0.42),  // sunlit top
                              shade);
        // Night dimming: moonlit clouds are much darker than sunlit ones,
        // but not invisible. 1.0 by day, 0.5 at night.
        float dayDim = mix(0.5, 1.0, IS_DAY);
        effect = cloudColor * cloud * 0.46 * dayDim;
    }

    vec3 bgFinal = iBackgroundColor + effect;
    vec3 outRgb = bgFinal * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
