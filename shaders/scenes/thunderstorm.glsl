// Thunderstorm — subtle ambient version. Sparse rain + infrequent dim
// lightning flashes. Background-only; text passes through.
//
// Flashes every ~15 sec, only ~30% of slots fire, ~25% of those get a
// secondary stutter. Flash intensity capped at 0.35 so it pulses the bg
// without strobing the text away.

float tsHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float tsRainLayer(vec2 uv, float speed, float density, float seed) {
    uv.x += uv.y * 0.14;
    vec2 grid = vec2(22.0, 10.0);
    vec2 q = uv * grid + seed;
    // Bound iTime + correct sign so drops fall DOWN — see rain.glsl for
    // the full sign derivation.
    q.y += mod(iTime, 100.0) * speed;
    vec2 cell = floor(q);
    vec2 f = fract(q);
    float h = tsHash(cell);
    if (h < 1.0 - density) return 0.0;
    float xPos = fract(h * 41.0);
    float dx = abs(f.x - xPos) * 75.0;
    // Per-streak length + asymmetric intensity, same as rain.glsl —
    // gives each drop character instead of identical clones.
    float streakLen = mix(0.22, 0.42, fract(h * 7.7));
    float streakBody = smoothstep(0.0, 0.04, f.y) *
                       smoothstep(streakLen, streakLen - 0.10, f.y);
    float intensity = mix(0.4, 1.0, f.y / streakLen);
    return exp(-dx * dx) * streakBody * intensity;
}

// Lightning timing — primary spike + two stuttered re-strikes at jittered
// per-slot offsets. Real lightning is chaotic; the previous single-offset
// stutter looked too clean.
float lightning(float t) {
    float period = 15.0;
    float slot = floor(t / period);
    float phase = fract(t / period);
    float fires = step(0.7, tsHash(vec2(slot, 1.0)));       // ~30% slots fire
    float primary = exp(-phase * period * 10.0);
    // Two stutters with hash-jittered timings — real strikes can fork.
    float stutter = step(0.55, tsHash(vec2(slot, 2.0)));
    float off1 = 0.010 + tsHash(vec2(slot, 3.0)) * 0.020;
    float off2 = 0.030 + tsHash(vec2(slot, 4.0)) * 0.030;
    float s1 = exp(-(phase - off1) * period * 14.0) * step(off1, phase);
    float s2 = exp(-(phase - off2) * period * 18.0) * step(off2, phase) * 0.6;
    float secondary = stutter * (s1 + s2);
    return (primary + secondary * 0.5) * fires;
}

// Spatial flash origin — every slot picks a random horizontal location
// (slightly biased toward the upper sky) so the flash reads as coming
// from "somewhere up and over there" rather than uniformly across the
// screen. Returns a 0..1 falloff multiplier for each fragment.
float flashLocality(vec2 uv, float t) {
    float slot = floor(t / 15.0);
    vec2 origin = vec2(tsHash(vec2(slot, 5.0)),
                       0.6 + tsHash(vec2(slot, 6.0)) * 0.3);
    return exp(-distance(uv, origin) * 1.8);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    // Flip uv.y so Shadertoy bottom-origin math works — see clear-day.glsl.
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;

    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // Far/near rain split — same parallax-depth treatment as rain.glsl,
    // slightly denser + faster for the storm.
    float rFar  = tsRainLayer(uv,                         2.5, 0.08, 0.0) * 0.5;
    float rNear = tsRainLayer(uv * 1.4 + vec2(0.4, 0.0),  3.6, 0.10, 5.7) * 0.7;

    vec3 farColor   = vec3(0.30, 0.33, 0.38);
    vec3 nearColor  = vec3(0.42, 0.46, 0.52);
    vec3 overcast   = vec3(-0.025, -0.022, -0.014);
    vec3 flashColor = vec3(0.85, 0.92, 1.00);
    // Lightning timing wraps every hour to stay in float32-safe range.
    float lt = mod(iTime, 3600.0);
    float flash = lightning(lt);
    // Spatial falloff: flash brighter near its origin, fades elsewhere.
    float spatial = flashLocality(uv, lt);

    // Rain briefly tinted by flash light — visible only during strikes.
    vec3 litFarColor  = farColor  + flashColor * flash * spatial * 0.3;
    vec3 litNearColor = nearColor + flashColor * flash * spatial * 0.3;

    vec3 effect = (litFarColor * rFar + litNearColor * rNear + overcast) * 0.5
                + flashColor * flash * spatial * 0.45;
    vec3 bgFinal = iBackgroundColor + effect;
    vec3 outRgb = bgFinal * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
