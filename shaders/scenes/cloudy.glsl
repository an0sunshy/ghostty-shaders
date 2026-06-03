// Cloudy — slow drifting cloud puffs. fbm noise thresholded into distinct
// soft-edged blobs that scroll horizontally. Background-only; text passes
// through.
//
// Tuned subtle: clouds tint the bg toward light grey only inside the puffs,
// the rest stays the user's Nightfox bg.
//
// IS_DAY (baked by ghostty-weather-swap from Open-Meteo's is_day, 1.0 day /
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

float cloudFbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * cloudNoise(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;

    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // Slow horizontal drift, bounded so iTime precision stays clean.
    // Slightly faster than before (0.012 → 0.018) — the previous pace
    // bordered on imperceptible.
    float t = mod(iTime, 1000.0) * 0.018;

    // Anisotropic sampling — clouds are wider than tall, sit in the upper
    // 70% of the canvas (sky).
    vec2 cp = vec2(uv.x * 2.5 + t, (uv.y - 0.15) * 1.2);
    float density = cloudFbm(cp);

    // Vertical density bias: cumulus thin out near the zenith and never
    // touch the horizon. Concentrates clouds in a mid-sky band.
    float vbias = smoothstep(0.95, 0.55, uv.y) * smoothstep(0.15, 0.45, uv.y);
    // Smooth threshold so puffs have soft edges instead of crisp shapes.
    float cloud = smoothstep(0.42, 0.62, density) * vbias;

    // Two-tone shading — sample fbm slightly offset and use the
    // difference as a per-pixel "bright top vs shaded underside" cue.
    // One extra fbm (3 noise samples). Sells puff volume cheaply.
    float d2 = cloudFbm(cp + vec2(0.0, 0.15));
    float shade = smoothstep(0.0, 0.25, density - d2);
    vec3 cloudColor = mix(vec3(0.22, 0.24, 0.28),  // shaded underside
                          vec3(0.36, 0.38, 0.42),  // sunlit top
                          shade);
    // Night dimming: moonlit clouds are much darker than sunlit ones, but
    // not invisible. 1.0 by day, 0.5 at night.
    float dayDim = mix(0.5, 1.0, IS_DAY);
    vec3 effect = cloudColor * cloud * 0.46 * dayDim;

    vec3 bgFinal = iBackgroundColor + effect;
    vec3 outRgb = bgFinal * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
