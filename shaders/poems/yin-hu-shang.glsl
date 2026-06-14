// Yin Hu Shang — 飲湖上初晴後雨 (Su Shi). West Lake in two moods at once:
//   水光潋灩晴方好，山色空濛雨亦奇
//   "Rippling water glittering — fine in clear weather;
//    hazy mountains dim in rain — wondrous too."
//
// Three layered, additive contributions on a near-black field, every
// channel >= 0, with heavy 留白 through the center where text sits:
//
//   1. FOREGROUND GLITTER (晴方好) — the lower third is a lake plane. A
//      traveling ripple field gates fine silver specular glints that pop
//      in and out as crests slide downward toward the viewer (潋灩). Dense
//      near the bottom edge, thinning fast upward so the center stays dark.
//
//   2. FAR-HILL MIST (山色空濛) — a faint hill silhouette behind a pale-grey
//      fog that "breathes": its density rides a slow sine so the hills
//      dissolve and reform. The hill body is just barely readable as a soft
//      darker-then-lighter ridge; the haze pools as a thin horizon glow.
//      Dim by design — this band is negative space.
//
//   3. RAIN CURTAIN (雨亦奇) — sparse fine streaks raked diagonally and
//      falling downward, low contrast — a drifting veil, not a downpour.
//
// Palette: jade-teal lake glints leaning silver #eaf6ff, pale grey mist
// #aab6bf, faint jade in the water highlights #11403c. Background is the
// host's iBackgroundColor; the effect is luminous-on-dark and additive.
//
// FLOAT-SAFETY: iTime is wrapped with mod(iTime, P) before any fast sin/cos
// or fract so a long-lived terminal never loses float32 precision. Slow
// continuous drift uses the wrapped clocks directly for seamless loops.
//
// FEELING DIALS: four shared knobs tune the scene without re-authoring it —
// GW_MOOD (global warm/cool tint), GW_ENERGY (mist-breathing + glint-twinkle
// AGITATION amplitude, never the rates), GW_DENSITY (glitter/rain/mist fill vs
// 留白), GW_GLOW (glint/streak/haze soft-edge bloom). All-default reproduces
// the authored look exactly.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls.
//   GW_MOOD    palette warmth: -1 cold/blue .. 0 neutral .. +1 warm (global tint)
//   GW_ENERGY  motion agitation: 0.3 still .. 1 .. 2 lively (mist breathing,
//              glint twinkle, rain head migration AMPLITUDE — never the rates)
//   GW_DENSITY fill vs 留白: 0.3 sparse .. 1 .. 1.8 lush (glitter gate window,
//              rain cell coverage, mist thickness)
//   GW_GLOW    bloom/softness: 0.6 crisp .. 1 .. 2.5 dreamy (glint/streak/haze
//              soft-edge radii)
#ifndef GW_MOOD
#define GW_MOOD 0.0
#endif
#ifndef GW_ENERGY
#define GW_ENERGY 1.0
#endif
#ifndef GW_DENSITY
#define GW_DENSITY 1.0
#endif
#ifndef GW_GLOW
#define GW_GLOW 1.0
#endif

float yhHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 2D value noise — smooth, used by the fbm below for mist + ripple fields.
float yhNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = yhHash(i);
    float b = yhHash(i + vec2(1.0, 0.0));
    float c = yhHash(i + vec2(0.0, 1.0));
    float d = yhHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 4-octave fbm for the soft rain-mist veils over the far hills.
float yhFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * yhNoise(p); p *= 2.03; a *= 0.5; }
    return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                 // host is top-origin → flip for math

    // iChannel0 is the terminal glyph layer only; sample UN-flipped.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    float aspect = iResolution.x / iResolution.y;

    // Wrapped clocks — seamless loops, never raw iTime into fast trig.
    float tRip  = mod(iTime, 120.0);   // ripple travel
    float tMist = mod(iTime, 240.0);   // slow mist breathing
    float tRain = mod(iTime, 90.0);    // rain fall

    // GW_ENERGY scales motion AGITATION (oscillation AMPLITUDE), never the
    // rates — scaling a sin(...*rate) argument would teleport elements when the
    // dial is dragged. eAmp = 1.0 at the default so the authored motion is kept.
    float eAmp = 0.45 + 0.55 * GW_ENERGY;

    // ---------------------------------------------------------------------
    // 1. FAR-HILL MIST (upper-middle band) — 山色空濛
    // ---------------------------------------------------------------------
    // A low, soft hill silhouette sits just above mid-screen. Two rounded
    // ridges via offset cosines. The hill body reads as a faint darker mass
    // capped by a brighter haze rim, so a far ridge is *just* legible behind
    // the rain ("山色"); the mist breathes on a slow sine so it veils and
    // clears ("空濛").
    float hillBase = 0.60;             // ridge crest height in uv.y
    // Two gentle humps — keep them shallow so most of the frame is empty.
    float ridge = hillBase
                + 0.055 * cos(uv.x * 4.0 + 0.7)
                + 0.030 * cos(uv.x * 9.0 - 1.3);

    // Slow breathing of the whole veil. Sine in [0,1] sets how thick the fog
    // is: dense → hills nearly vanish; thin → a little more ridge shows. The
    // SWING around its midpoint is the agitation GW_ENERGY scales (rate stays
    // fixed): low energy = a near-still veil, high = it breathes more deeply.
    float breathe = 0.5 + 0.5 * sin(tMist * 0.131) * eAmp;   // ~48s period feel
    breathe = clamp(breathe, 0.0, 1.0);

    // Drifting fog texture: slow horizontal crawl + tiny vertical lift.
    vec2 mp = vec2(uv.x * aspect * 1.5 + tMist * 0.018,
                   uv.y * 2.2 - tMist * 0.006);
    float fog = yhFbm(mp);
    fog = fog * fog;                                   // bias toward wisps

    // Hill body: a faint glow that peaks just BELOW the ridge line (the lit
    // far slope catching grey daylight through rain) and a slightly brighter
    // rim right AT the crest. Both very dim — this must read as veiled hills,
    // not a solid wall. When the fog breathes thick, the body is more hidden.
    // GW_GLOW widens the hill/haze feather radii (softer, dreamier veiling).
    float below   = smoothstep(0.14 * GW_GLOW, 0.0, ridge - uv.y) * step(uv.y, ridge);
    float rim     = smoothstep(0.045 * GW_GLOW, 0.0, abs(uv.y - ridge));
    float hill    = (below * 0.22 + rim * 0.40) * mix(1.0, 0.45, breathe);

    // Horizon haze: the brightest part of the band is a thin pale rim of
    // mist clinging just above the ridge, feathering up into emptiness.
    float haze = smoothstep(hillBase - 0.04, hillBase + 0.18, uv.y)
               * smoothstep(0.95, 0.62, uv.y);
    // GW_DENSITY thickens (or thins) the veil — lusher fog vs more 留白.
    float mistDensity = mix(0.30, 0.70, breathe) * GW_DENSITY;

    // Vertical envelope keeps the whole band in the upper-middle, fading to
    // zero before the lake glitter band below so the foreground is untouched.
    float mistBand = smoothstep(0.34, hillBase, uv.y)
                   * smoothstep(1.0, 0.66, uv.y);
    float mist = (fog * haze * mistDensity + hill) * mistBand;

    // Mist color: pale cool grey #aab6bf, very slightly green-grey to tie
    // the hills to the jade lake. Kept gentle — this band is 留白.
    vec3 mistColor = vec3(0.665, 0.713, 0.748);
    vec3 mistContribution = mistColor * mist * 0.30;

    // ---------------------------------------------------------------------
    // 2. FOREGROUND LAKE GLITTER (lower third) — 水光潋灩晴方好
    // ---------------------------------------------------------------------
    // A traveling specular-sparkle field. A smooth, slow ripple field sets
    // where crests are; a fast, fine point field carves them into discrete
    // sparks. Both scroll DOWNWARD (uv increases downward after the flip's
    // lake band is anchored at the bottom), so crests march toward the
    // viewer and glints pop in/out (潋灩) rather than smear.
    //
    // Lake envelope: only the bottom band carries glitter, fading out upward
    // toward the mist. Squared so density falls off faster from the bottom
    // edge — the foreground water is anchored low, thinning quickly.
    float lakeBand = smoothstep(0.40, 0.0, uv.y);     // 0 at mid, 1 at bottom
    lakeBand *= lakeBand;

    // Aspect-correct x so the sparkle isn't stretched on wide windows. The
    // +tRip terms scroll the fields; positive y-shift moves crests downward.
    vec2 rp = vec2(uv.x * aspect, uv.y);

    // Smooth ripple "swell": two crossing low-frequency waves give a lively,
    // non-repeating crest pattern that travels toward the bottom.
    float w1 = yhNoise(rp * vec2(8.0, 14.0)  + vec2( tRip * 0.30, tRip * 0.55));
    float w2 = yhNoise(rp * vec2(13.0, 22.0) + vec2(-tRip * 0.22, tRip * 0.78));
    float swell = w1 * 0.6 + w2 * 0.4;

    // Fine point field: small, numerous specks that ride on the swell. Higher
    // frequency → tiny glints rather than chips. Also scrolls downward.
    float spark = yhNoise(rp * vec2(85.0, 150.0) + vec2(tRip * 1.1, tRip * 2.4));

    // Gate: a glint lights only where a crest of the swell AND a peak of the
    // spark field coincide. Narrow windows make individual points twinkle in
    // and out as the fields slide under threshold (潋灩) — crisp and sparse.
    //
    // GW_DENSITY drops the lower gate thresholds so MORE crests/peaks clear the
    // bar (lusher glitter) or raises them for a sparser water. GW_GLOW widens
    // the smoothstep span (lower edge pulled further below the fixed upper edge)
    // so glints feather in softly — wider, dreamier — vs a crisp pop. Both reduce
    // to the authored windows (0.58..0.78, 0.80..0.97) at default 1.0.
    float dShift  = (GW_DENSITY - 1.0) * 0.10;
    float crestHi = 0.78;
    float ptsHi   = 0.97;
    float crestLo = clamp(crestHi - (crestHi - (0.58 - dShift)) * GW_GLOW, 0.0, crestHi - 0.001);
    float ptsLo   = clamp(ptsHi   - (ptsHi   - (0.80 - dShift)) * GW_GLOW, 0.0, ptsHi   - 0.001);
    float crest = smoothstep(crestLo, crestHi, swell);
    float pts   = smoothstep(ptsLo, ptsHi, spark);
    float glint = crest * pts;

    // Per-fragment twinkle so even lit glints shimmer rather than sit. Phase
    // varies by position so they don't blink in unison. GW_ENERGY scales the
    // shimmer AMPLITUDE (depth) around its mean, not the blink rate.
    float ph = yhHash(floor(rp * vec2(85.0, 150.0)));
    float twinkle = 0.55 + 0.45 * eAmp * sin(tRip * (2.4 + ph * 3.6) + ph * 6.2831);
    twinkle = clamp(twinkle, 0.0, 1.0);

    float glitter = glint * twinkle * lakeBand;

    // Glint color: brilliant silver #eaf6ff with a faint jade-teal cast so
    // the water keeps West Lake's green soul.
    vec3 glintColor = vec3(0.86, 0.94, 0.98);
    // A faint broad jade sheen across the lake band — the water's own dim
    // color, well below the glints so text below isn't washed.
    vec3 waterSheen  = vec3(0.067, 0.251, 0.235);     // jade-teal #11403c
    vec3 lakeContribution = glintColor * glitter * 1.25
                          + waterSheen * lakeBand * 0.10;

    // ---------------------------------------------------------------------
    // 3. RAIN CURTAIN (whole frame, sparse) — 雨亦奇
    // ---------------------------------------------------------------------
    // Fine diagonal streaks, low contrast — a drifting veil, not a storm.
    // Coarse grid, low density; raked ~20° via the x-shear on uv.y; the
    // streaks fall downward (tRain increases the sampled y so each cell's
    // bright head migrates toward the bottom).
    vec2 ruv = uv;
    ruv.x += ruv.y * 0.38;                            // diagonal rake
    vec2 rgrid = vec2(30.0, 15.0);
    vec2 rq = ruv * rgrid;
    rq.y += tRain * 3.4;                              // fall direction (down)
    vec2 rcell = floor(rq);
    vec2 rf = fract(rq);
    float rh = yhHash(rcell);
    float rain = 0.0;
    // GW_DENSITY lowers the cell keep-threshold so MORE cells carry a streak
    // (denser rain) or fewer for a thinner veil; default keeps ~12% active.
    float rainThresh = clamp(0.88 - (GW_DENSITY - 1.0) * 0.10, 0.0, 0.995);
    if (rh > rainThresh) {
        float xPos = fract(rh * 41.0);
        // GW_GLOW softens the streak: a wider Gaussian cross-section and a
        // longer feathered tail read as a dreamier veil; default = authored.
        float dx = abs(rf.x - xPos) * (64.0 / GW_GLOW);
        float streakLen = mix(0.30, 0.58, fract(rh * 7.7));
        float body = smoothstep(0.0, 0.05 * GW_GLOW, rf.y)
                   * smoothstep(streakLen, streakLen - 0.16 * GW_GLOW, rf.y);
        float headBright = mix(0.30, 1.0, rf.y / streakLen);
        rain = exp(-dx * dx) * body * headBright;
    }
    // Rain fades slightly toward the very top so it merges with the haze
    // instead of cutting hard lines across the 留白.
    float rainFade = mix(0.65, 1.0, smoothstep(1.0, 0.4, uv.y));
    vec3 rainColor = vec3(0.62, 0.69, 0.74);          // cool pale grey
    vec3 rainContribution = rainColor * rain * rainFade * 0.26;

    // ---------------------------------------------------------------------
    // COMPOSITE — additive, luminous-on-dark, text passes through.
    // ---------------------------------------------------------------------
    vec3 effect = mistContribution + lakeContribution + rainContribution;
    effect = max(effect, 0.0);                        // every channel >= 0

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (lake glints, hill
    // mist, and rain alike) so the feeling reads at a glance — cold/bleak (-1)
    // through the authored silver-jade (0) to warm/tender (+1). Default 0 =
    // identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;
    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}