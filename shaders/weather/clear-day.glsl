// Clear Day — sun arcing across the sky. Time of day is BAKED IN at swap
// time as #define TIME_OF_DAY_BASE (seconds since midnight). iTime keeps
// the sun advancing continuously while the window stays open, no
// re-swap needed.
//
// Why baked rather than uniform: Ghostty 1.3.1 doesn't yet supply iDate
// (see `ghostty +show-config --default --docs` — listed as NOT CURRENTLY
// SUPPORTED). So we can't compute time-of-day inside the shader from
// stable inputs. The swap script injects TIME_OF_DAY_BASE at copy time.
//
// Background-only; text passes through. Minimal animation (corona pulse).

#ifndef TIME_OF_DAY_BASE
#define TIME_OF_DAY_BASE 43200.0  // fallback: noon, if the swap script didn't inject
#endif

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    // Ghostty's fragCoord uses Metal's top-origin convention (y=0 at top),
    // opposite of Shadertoy's bottom-origin. Flip uv.y once so the rest of
    // this shader reads naturally (high y = top of sky).
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;

    // Sample iChannel0 with the ORIGINAL (un-flipped) coord — it's a texture
    // and follows its own coord system. Anti-aliased text edges rely on this.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // Bake time-of-day exactly from TIME_OF_DAY_BASE; do NOT add iTime.
    // Ghostty's iTime is "seconds since first frame" and can be in the
    // hundreds of thousands for a long-lived window — float32 precision
    // collapses the math at that magnitude. The swap script (called on
    // focus events / cycle) re-bakes TIME_OF_DAY_BASE each invocation,
    // so the position stays current without needing iTime advancement.
    float t = TIME_OF_DAY_BASE / 86400.0;

    // Map raw hour t∈[0,1] onto daytime arc t∈[0,1] over 6am..6pm.
    // Outside that window the sun is below horizon (off-screen).
    float sunDay = clamp((t - 0.25) / 0.50, 0.0, 1.0);
    float sunHeight = 1.0 - pow(abs(sunDay - 0.5) * 2.0, 1.6);
    vec2 sunPos = vec2(sunDay, 0.15 + 0.55 * sunHeight);

    // Aspect-correct distance so sun stays circular at any window size.
    vec2 aspect = vec2(iResolution.x / iResolution.y, 1.0);
    float d = length((uv - sunPos) * aspect);

    float disk   = smoothstep(0.040, 0.034, d);
    // Corona/glow magnitudes intentionally below the moon's halo in
    // clear-night.glsl — the sun at noon has bright surroundings so it
    // doesn't need to dominate; the moon at night is the only light
    // source against dark sky and reads brighter.
    float corona = exp(-d * 11.0) * 0.20;
    float glow   = exp(-d * 4.0)  * 0.04;

    // Subtle ray pulse — mod iTime to keep it in float32-safe range.
    float pulse = 1.0 + 0.08 * sin(mod(iTime, 100.0) * 0.4);
    corona *= pulse;
    glow   *= pulse;

    // Sun color: warm at horizon, near-white at zenith. Slightly desaturated
    // so the disk reads as "small bright sun" not "bright lamp".
    vec3 sunCoreColor   = mix(vec3(0.95, 0.78, 0.45),
                              vec3(0.95, 0.93, 0.82), sunHeight);
    vec3 sunCoronaColor = mix(vec3(0.90, 0.60, 0.35),
                              vec3(0.90, 0.80, 0.60), sunHeight);

    // Sky tint kept VERY subtle: a faint cool hint at noon, a touch of
    // warmth only when the sun is near horizon. Most of the bg stays the
    // user's Nightfox oceanic blue — we don't wash it out.
    //
    // The warmth now radiates directionally from the sun's azimuth so
    // sunrise/sunset reads as "the sky is warm near the sun" instead of
    // a uniform horizon band. Adds one `exp` per pixel.
    float warmth = pow(abs(sunDay - 0.5) * 2.0, 1.6);
    float horizDist = abs(uv.x - sunDay);
    float warmHalo = exp(-horizDist * 2.5) * warmth;
    vec3 skyTint = mix(vec3(0.02, 0.04, 0.06),    // dim oceanic at noon
                       vec3(0.10, 0.05, 0.025), warmHalo);
    // Slight vertical gradient — more tint near horizon, less at zenith.
    skyTint *= mix(0.35, 1.0, smoothstep(0.0, 1.0, 1.0 - uv.y));
    // Zenith cool lift at noon: tiny push toward blue overhead when the
    // sun is high. Negligible cost, gives the noon sky a real "blue
    // overhead, warmer near horizon" feel.
    skyTint += vec3(-0.005, 0.0, 0.012) * smoothstep(0.0, 1.0, uv.y) * (1.0 - warmth);

    // If sun is below the horizon (early morning / late evening), suppress
    // disk + corona but keep dim sky tint.
    float dayMask = step(0.001, sunHeight);

    vec3 effect = vec3(0.0);
    effect += sunCoreColor   * disk   * dayMask;
    effect += sunCoronaColor * corona * dayMask;
    effect += sunCoronaColor * glow   * 0.5 * dayMask;
    effect += skyTint;

    // Composite: synthesize bg = iBackgroundColor + effect, then put text
    // over it with standard "over" blending (assumes iChannel0 uses
    // premultiplied alpha, which is the standard for compositing pipelines).
    vec3 bgFinal = iBackgroundColor + effect;
    vec3 outRgb = bgFinal * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
