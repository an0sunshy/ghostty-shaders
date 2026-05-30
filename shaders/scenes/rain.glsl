// Rain — subtle ambient. Sparse slow grey streaks, low contrast against
// the bg. Goal is "you notice it's drizzling out the corner of your eye"
// not "rain in the terminal".
//
// Grid 22×10 with density 0.06/0.08 gives ~16 partial streaks visible at
// any moment. Color is neutral grey (not blue), contribution kept small
// so the effect reads as a misty wash rather than discrete drops.

float rainHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float rainLayer(vec2 uv, float speed, float density, float seed) {
    uv.x += uv.y * 0.12;                       // gentle wind tilt
    vec2 grid = vec2(22.0, 10.0);              // coarse → fewer drops
    vec2 q = uv * grid + seed;
    // Bound iTime by mod so float32 precision survives across long-lived
    // windows (iTime can grow to 10^5+ seconds; multiplied by speed it
    // blows past float precision and the floor(q) hash quantizes wrong).
    // Period of 100 sec is plenty for visual continuity.
    //
    // SIGN: q.y += time*speed means the screen "scrolls up" through the
    // rain world over time, so a streak at a fixed q.y appears at LOWER
    // uv.y over time. In post-flip Shadertoy convention, lower uv.y =
    // closer to the bottom of the screen. Net visible motion: streaks
    // fall DOWN. (Earlier `q.y -= ...` had the opposite sign and rain
    // visually moved upward.)
    q.y += mod(iTime, 100.0) * speed;
    vec2 cell = floor(q);
    vec2 f = fract(q);
    float h = rainHash(cell);
    if (h < 1.0 - density) return 0.0;
    float xPos = fract(h * 41.0);
    float dx = abs(f.x - xPos) * 80.0;
    // Per-streak length variation via the existing hash. Streaks aren't
    // all identical — some short, some longer — for character.
    float streakLen = mix(0.22, 0.42, fract(h * 7.7));
    float streakBody = smoothstep(0.0, 0.04, f.y) *
                       smoothstep(streakLen, streakLen - 0.10, f.y);
    // Asymmetric brightness: drop heads (bottom of streak) brighter than
    // tails (top), matching how real raindrops illuminate.
    float intensity = mix(0.4, 1.0, f.y / streakLen);
    return exp(-dx * dx) * streakBody * intensity;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    // Flip uv.y so Shadertoy bottom-origin math works — otherwise rain
    // would fall upward on screen (Ghostty uses Metal top-origin).
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;

    // iChannel0 is text-only; sample with the original (un-flipped) coord.
    // See clear-day.glsl for the synthesized-bg pattern.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // 2 sparse layers with separate color contributions so far/near rain
    // visibly differ — far layer is mistier (cooler & darker), near
    // layer is a touch brighter. Sells parallax depth.
    float rFar  = rainLayer(uv,                         2.0, 0.06, 0.0) * 0.5;
    float rNear = rainLayer(uv * 1.4 + vec2(0.4, 0.0),  3.0, 0.08, 5.7) * 0.7;

    vec3 farColor  = vec3(0.30, 0.33, 0.38);   // desaturated, atmospheric
    vec3 nearColor = vec3(0.42, 0.46, 0.52);   // crisper, nearer
    vec3 overcast  = vec3(-0.015, -0.013, -0.008);

    // Lower overall multiplier than before — streaks merge into the bg.
    vec3 effect = (farColor * rFar + nearColor * rNear + overcast) * 0.45;
    vec3 bgFinal = iBackgroundColor + effect;
    vec3 outRgb = bgFinal * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
