// Feng Xue Su — 逢雪宿芙蓉山主人 (Liu Changqing)
//   柴門聞犬吠，風雪夜歸人。
//   "At the brushwood gate a dog barks — through wind and snow,
//    someone comes home in the night."
//
// A night blizzard at a remote cottage. One warm lit lantern hangs low and
// off-center at the brushwood gate; everything else is dark, wind-driven
// snow. Cold steel-blue snow streaks are raked at ~30deg and FALL toward the
// lower-left (a real gale off the mountain, not a vertical drift), gusting in
// sinusoidal density waves. The lantern sways and its bloom pulses with each
// gust; the snow scatters warm where it crosses the glow. A faint dark-warm
// blob — the returning figure — eases slowly inward from the frame edge
// toward the single point of warmth.
//
// 留白: the upper sky stays near-black for text; the light is concentrated in
// one focal lantern low and to the side. Background-only; text passes through.
//
// Four "feeling" dials tune the scene from one set of controls (all-default
// reproduces the authored look): GW_MOOD warms/cools the whole gale and lamp;
// GW_ENERGY drives the gust agitation (lantern sway + an extra above-default
// flurry), not the fall rate; GW_DENSITY thickens/thins the streak coverage and
// haze veil (留白); GW_GLOW softens or sharpens the lantern bloom and streaks.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls.
#ifndef GW_MOOD
#define GW_MOOD 0.0      // palette warmth: -1 cold/blue .. 0 neutral .. +1 warm
#endif
#ifndef GW_ENERGY
#define GW_ENERGY 1.0    // motion: 0.3 still/meditative .. 1 .. 2 lively
#endif
#ifndef GW_DENSITY
#define GW_DENSITY 1.0   // fill vs 留白: 0.3 sparse/empty .. 1 .. 1.8 lush
#endif
#ifndef GW_GLOW
#define GW_GLOW 1.0      // bloom/softness: 0.6 crisp .. 1 .. 2.5 dreamy
#endif

float fxHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 2D value noise + 3-octave fbm — used for the soft turbulence of the
// gusting snow veil and the figure's blurred edge.
float fxNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = fxHash(i);
    float b = fxHash(i + vec2(1.0, 0.0));
    float c = fxHash(i + vec2(0.0, 1.0));
    float d = fxHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fxFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 3; i++) { v += a * fxNoise(p); p *= 2.07; a *= 0.5; }
    return v;
}

// One layer of wind-raked snow streaks. The coordinate frame is rotated so
// its y-axis points DOWNWIND (the direction the snow falls: down and to the
// left, ~30deg off vertical). Each filled cell holds a short luminous streak
// elongated along that downwind axis. Advancing time slides every streak
// ALONG that same axis toward the lower-left, so each streak travels down its
// own length — the orientation matches the direction of fall.
// `windAngle` and `gust` are shared by all layers so the whole gale breathes
// as one. Returns a scalar streak intensity in [0, ~1].
float snowStreaks(vec2 p, float scale, float speed, float density,
                  float seed, float windAngle, float gust, float t) {
    // Rotate so +y of the local frame runs downwind. The wind blows toward
    // the lower-left, so the downwind direction in screen space (uv.y down)
    // is (-sin a, +cos a). We project p onto that axis (q.y) and onto its
    // perpendicular (q.x).
    float ca = cos(windAngle), sa = sin(windAngle);
    // downwind axis d = (-sa, ca); cross axis c = (ca, sa)
    vec2 r = vec2(p.x * ca + p.y * sa,     // along cross axis
                  -p.x * sa + p.y * ca);   // along downwind axis (+ = downwind)

    vec2 q = r * scale + seed;
    // Snow FALLS downwind: as t grows, features move toward larger downwind
    // projection (down + left, since uv.y is down). ADDING to the sampled
    // coordinate makes the pattern translate in the +downwind direction —
    // streaks descend along the rake, not rise against it. mod()'d t upstream
    // keeps inputs bounded so the loop never loses float precision.
    q.y += t * speed;

    vec2 cell = floor(q);
    float h = fxHash(cell);
    // Gust raises the effective density: more streaks during a strong gust.
    float thresh = 1.0 - density * (0.55 + 0.75 * gust);
    if (h < thresh) return 0.0;

    vec2 f = fract(q);
    vec2 center = vec2(fract(h * 17.3), 0.5);
    vec2 d = f - center;
    // Elongate along the downwind axis (y), thin across it (x) -> a streak.
    // Gust stretches the streaks longer and faster-looking.
    float lenScale = mix(2.6, 4.2, gust);
    float across = abs(d.x) * 9.0;
    float along  = abs(d.y) * lenScale;
    float streak = exp(-(across * across) - (along * along));
    // Per-streak brightness jitter so the field isn't uniform.
    streak *= mix(0.6, 1.0, fract(h * 53.1));
    return streak;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;

    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    float aspect = iResolution.x / iResolution.y;
    // Aspect-corrected coordinate for round shapes (lantern bloom, figure).
    vec2 ac = vec2(uv.x * aspect, uv.y);

    // --- The gale ---------------------------------------------------------
    // One slow wind envelope drives everything: density swells and ebbs, and
    // the rake angle wobbles a few degrees, so gusts feel alive. Two periods
    // multiplied give an irregular, non-mechanical breathing. mod() wraps
    // iTime so the fast oscillation never loses float precision.
    float tGust = mod(iTime, 60.0);
    float gust = 0.5 + 0.5 * sin(tGust * 0.9)
                     * (0.6 + 0.4 * sin(tGust * 0.37 + 1.3));
    gust = clamp(gust, 0.0, 1.0);

    // Base rake ~30deg from vertical; gust nudges it steeper into the wind.
    float windAngle = radians(30.0) + (gust - 0.5) * radians(10.0);

    // Slow continuous travel for the streaks (drift, fract-safe via mod).
    float tFlow = mod(iTime, 120.0);

    // Three parallax layers of streaks: far/dim, mid, near/bright.
    // GW_DENSITY scales how many cells carry a streak (coverage), so >1 packs a
    // thicker blizzard and <1 opens up the 留白. Default 1.0 = authored density.
    float dens = GW_DENSITY;
    float snow = 0.0;
    snow += snowStreaks(ac, 11.0, 3.2, 0.05 * dens, 0.0, windAngle, gust, tFlow) * 0.40;
    snow += snowStreaks(ac, 16.0, 4.6, 0.06 * dens, 3.7, windAngle, gust, tFlow) * 0.62;
    snow += snowStreaks(ac, 23.0, 6.2, 0.07 * dens, 7.3, windAngle, gust, tFlow) * 0.85;

    // A faint drifting turbulence veil so the blizzard reads as volume, not
    // just discrete streaks. Kept very dim and concentrated low so the upper
    // sky stays open. Scrolls downwind (down + slightly left, uv.y down) over
    // the loop, so the haze drifts with the falling streaks rather than against
    // them.
    vec2 veilUv = ac * 2.3 + vec2(tFlow * 0.18, -tFlow * 0.55);
    float veil = fxFbm(veilUv) * fxFbm(veilUv * 1.9 + 5.0);
    veil *= smoothstep(1.0, 0.15, uv.y);            // fade out toward the top
    veil *= (0.10 + 0.16 * gust);                   // breathes with the gale
    veil *= GW_DENSITY;                             // lusher/sparser volume haze

    // --- The lantern at the brushwood gate --------------------------------
    // Low and off-center. It sways gently on the wind, and its bloom pulses
    // brighter with each gust — the warm heart of the scene.
    // GW_ENERGY scales the AGITATION (sway amplitude), not the oscillator rate,
    // so dialing it reads as a calm<->stormy wind rather than teleporting the
    // lantern. eAmp = 1.0 at default; an extra gust-coupled swing grows only
    // above default so high energy buffets the lamp harder.
    float eAmp = 0.45 + 0.55 * GW_ENERGY;                       // 1.0 at default
    float tSway = mod(iTime, 40.0);
    float sway = (sin(tSway * 0.8) * 0.012 + sin(tSway * 1.9 + 0.7) * 0.005) * eAmp;
    sway += sin(mod(iTime, 27.0) * 1.3 + gust * 3.0) * 0.010 * max(GW_ENERGY - 1.0, 0.0);
    vec2 lanternPos = vec2(0.30 * aspect + sway, 0.30);
    float ld = length(ac - lanternPos);

    // Pulsing intensity: a steady glow plus a gust-coupled flicker.
    float pulse = 0.78 + 0.22 * gust
                + 0.06 * sin(mod(iTime, 30.0) * 5.3);
    // Two-scale bloom: a tight bright core and a wide soft halo. GW_GLOW scales
    // the bloom RADII (dividing the exp falloff coefficient widens the glow), so
    // >1 = softer/dreamier halo, <1 = crisper lamp. Default 1.0 = authored.
    float core = exp(-ld * 42.0 / GW_GLOW);
    float halo = exp(-ld * 8.5 / GW_GLOW);
    float lanternGlow = (core * 1.10 + halo * 0.55) * pulse;

    // A tiny hot point so the lamp itself reads as a source, not just haze.
    float flame = exp(-ld * 150.0 / GW_GLOW) * (0.9 + 0.25 * sin(mod(iTime, 12.0) * 9.0));

    // --- The returning figure ---------------------------------------------
    // 風雪夜歸人 — a dim, dark-warm blob eases in from the right edge toward
    // the lantern over a long loop, never quite arriving. It is darker than
    // the snow around it (a silhouette) but carries a faint warm rim from the
    // lamplight, so it reads as a person, not a hole.
    float tWalk = mod(iTime, 90.0) / 90.0;          // 0..1 over the loop
    // Ease from edge toward (but stopping short of) the lantern.
    float walk = smoothstep(0.0, 1.0, tWalk);
    vec2 figPos = mix(vec2(0.95 * aspect, 0.25),
                      vec2(0.48 * aspect, 0.27), walk);
    // A soft vertical ellipse, edge dissolved by the blizzard.
    vec2 fd = (ac - figPos) / vec2(0.052, 0.105);
    float figR = length(fd);
    float figBlur = fxFbm(ac * 9.0 + tFlow * 0.3) * 0.30 * eAmp; // edge churn scales with energy
    float figMask = smoothstep(1.15 + figBlur, 0.40, figR);
    // Visible only mid-walk (fades in from the edge, hasn't reached the gate).
    figMask *= smoothstep(0.0, 0.18, tWalk) * smoothstep(1.0, 0.80, tWalk);

    // --- Compose the luminous contribution --------------------------------
    // Snow is cold steel-blue, but warms toward amber where it passes through
    // the lantern's reach (the streaks scatter the lamplight).
    vec3 snowCold = vec3(0.62, 0.72, 0.86);         // steel-blue #9fb6d8-ish
    vec3 snowWarm = vec3(1.00, 0.74, 0.42);         // scattered amber
    float nearLamp = exp(-ld * 6.0 / GW_GLOW);      // warm influence falloff (glow widens reach)
    vec3 snowColor = mix(snowCold, snowWarm, nearLamp * 0.85);

    vec3 lanternColor = vec3(1.00, 0.68, 0.34);     // amber #ffae57-ish
    vec3 flameColor   = vec3(1.00, 0.86, 0.62);

    vec3 effect = vec3(0.0);
    effect += snowColor * snow * 0.55;              // the gale of streaks
    effect += snowCold * veil;                      // faint volume haze
    effect += lanternColor * lanternGlow * 0.62;    // the warm bloom
    effect += flameColor * flame * 0.9;             // the hot lamp point

    // The figure: subtract where the silhouette blocks snow, then add a warm
    // lamplit rim so it reads as a person leaning into the gale, not a void.
    // The rim is strongest on the side facing the lantern. Net stays >= 0.
    float lampSide = exp(-length(ac - lanternPos) * 4.5 / GW_GLOW);
    float warmRim = figMask * (0.35 + 0.65 * lampSide);
    effect *= (1.0 - 0.70 * figMask);               // darken: a silhouette
    effect += vec3(0.62, 0.38, 0.20) * warmRim * 0.85; // warm lamplit rim
    effect = max(effect, 0.0);                       // every channel >= 0

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (snow, veil, lantern,
    // and figure rim alike) so the feeling reads at a glance — cold/bleak (-1)
    // through the authored steel-and-amber (0) to warm/tender (+1). Default 0 =
    // identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;

    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
