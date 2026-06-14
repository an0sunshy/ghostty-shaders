// 江雪 (Jiāng Xuě) — River Snow — Liu Zongyuan
//   孤舟蓑笠翁，獨釣寒江雪。
//   "A lone boat, a straw-cloaked old man, fishing alone in the cold river snow."
//
// The poem IS 留白: total white emptiness over a black river, all peaks and
// paths erased by snow, one tiny boat with a solitary figure at the dead
// center of the void. We render that as near-total dark with:
//   * the SNOW as the dominant presence — cool-grey grains over THREE
//     parallax layers, drifting clearly straight DOWN (toward the bottom)
//     with a faint lateral wander; soft, slightly vertically-stretched so
//     they read as falling flakes, not twinkling stars. Density is layered:
//     enough to feel like weather covering everything, yet open enough at
//     mid-frame that glyphs still sit in dark;
//   * a low cold river-mist that the snow settles into along the bottom;
//   * one dim warm ember low-center (the lone boat and its cloaked man) —
//     deliberately small and faint, the single point of life in the cold,
//     suggested as a tiny hull-smear with a soft glow, swaying almost
//     imperceptibly. No tall pole: just a hair of reflection on the water.
//
// Palette: ink-black #05060a -> cold pewter #b6cff5 snow -> one amber ember
// #ffbc6b. Additive, luminous-on-dark. Most of the frame stays near-zero.

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

// --- hash / value-noise / fbm (inlined, house style) -----------------------
float jxHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float jxNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = jxHash(i);
    float b = jxHash(i + vec2(1.0, 0.0));
    float c = jxHash(i + vec2(0.0, 1.0));
    float d = jxHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float jxFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * jxNoise(p); p *= 2.03; a *= 0.5; }
    return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                       // host is top-origin: uv.y=1 top

    // Sample the terminal glyph layer with the UNFLIPPED coord.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    float aspect = iResolution.x / iResolution.y;

    vec3 effect = vec3(0.0);

    vec3 snowCol = vec3(0.71, 0.81, 0.96);   // #b6cff5-ish cold pewter (GW_MOOD applied globally below)

    // ------------------------------------------------------------------
    // SNOW — the dominant presence. Three parallax layers of cool-grey
    // grains drifting clearly straight DOWN. A cell grid scrolls downward;
    // occupied cells hold one soft, slightly vertically-stretched flake so
    // the eye reads "falling snow", not "twinkling stars". Back layers are
    // denser/dimmer/faster-scrolling-in-cells (far, small, many); the front
    // layer is sparser and larger (near). Together they blanket the frame
    // the way the poem's snow erases every peak and path — yet stay dim
    // enough that text still sits in the dark between flakes.
    //
    // Vertical scroll via fract() of (uv.y*rows + fall*iTime): adding to the
    // row coordinate as time grows translates the pattern toward the bottom
    // (screen-down), and the per-row fract() makes it seamless and float-safe
    // (no raw iTime into a fast trig argument; sway wrapped with mod()).
    // ------------------------------------------------------------------
    const int LAYERS = 3;
    for (int L = 0; L < LAYERS; L++) {
        float fl = float(L);
        float t  = fl / 2.0;                 // 0, 0.5, 1 across the layers

        // Grid resolution: wider than tall so flakes are round-ish after
        // aspect correction. Back layer densest+smallest, front sparsest.
        float cols = mix(20.0, 9.0, t);
        float rows = mix(26.0, 12.0, t);

        // Fall speed in CELLS per second. The far layer has more rows, so to
        // keep on-screen pixel speed natural the cell-rate rises a bit toward
        // the back. All clearly visible across a few seconds — real snowfall.
        float fall = mix(1.05, 0.55, t);   // base fall rate (energy = agitation, not rate)

        vec2 g = vec2(uv.x * cols, uv.y * rows + fall * iTime);
        vec2 cell = floor(g);
        vec2 f = fract(g);

        // Per-cell random.
        float h = jxHash(cell + fl * 37.0);

        // Density: a healthy fraction of cells carry a flake so it reads as
        // weather, but never a solid sheet. Back layers slightly denser.
        // GW_DENSITY: lower the keep-threshold to carry MORE flakes (lush) or
        // raise it for sparser 留白. density=1 leaves the authored threshold.
        float thresh = mix(0.62, 0.74, t) - (GW_DENSITY - 1.0) * 0.22;
        thresh = clamp(thresh, 0.05, 0.96);
        if (h > thresh) {
            // Flake position inside the cell.
            float px = fract(h * 17.3);
            float py = fract(h * 31.7);

            // Horizontal wander: tiny per-flake sway (a flutter, not a slide).
            // Wrap iTime with mod() for a seamless loop.
            float swPhase = h * 6.2831853;
            float swSpeed = 0.6 + h * 0.9;
            // GW_ENERGY scales AGITATION (sway amplitude + a shared lateral gust),
            // NOT the motion rate — so dialing it reads as calm<->lively wind
            // instead of teleporting flakes to new positions. Default (1.0) keeps
            // the authored sway and adds no gust.
            float eAmp = 0.45 + 0.55 * GW_ENERGY;                          // 1.0 at default
            float sway = sin(mod(iTime, 33.0) * swSpeed + swPhase) * 0.10 * eAmp;
            float gust = sin(mod(iTime, 29.0) * 0.4 + uv.y * 3.5) * 0.08 * max(GW_ENERGY - 1.0, 0.0);
            px += sway + gust;

            // Aspect-correct in-cell distance; stretch slightly VERTICALLY so
            // the flake reads as falling (a soft short streak) rather than a
            // round star. Dividing y by <1 lengthens the splat along y.
            float cellAspect = aspect * (rows / cols);
            vec2 d = (f - vec2(px, py)) * vec2(cellAspect, 0.72);
            float dist = length(d);

            // Flake size: front layer larger (nearer), but kept modest so
            // near flakes still read as snow rather than soft orbs.
            float grainR = mix(0.058, 0.090, t) * GW_GLOW;   // GW_GLOW: softer/dreamier flakes
            float grain = smoothstep(grainR, 0.0, dist);

            // Very gentle, slow brightness breathing — atmosphere, NOT the
            // sharp star-twinkle of a clear night. Kept narrow so flakes
            // never blink like stars.
            float br = 0.85 + 0.15 * sin(mod(iTime, 31.0) * (0.5 + h * 0.6) + h * 12.0);

            // Far layers dimmer (aerial depth through the falling snow).
            float bright = mix(0.34, 0.60, t) * br;
            effect += snowCol * grain * bright;
        }
    }

    // ------------------------------------------------------------------
    // COLD RIVER-MIST — the snow settles into a low band of cold haze along
    // the bottom (the 寒江 surface). Soft, broken by slow fbm so it is never
    // a flat bar, and weak enough that it only lifts the lowest fifth of the
    // frame. This is where the void meets the black water.
    // ------------------------------------------------------------------
    float band = 1.0 - smoothstep(0.0, 0.20, uv.y);      // strongest at bottom edge
    float mistN = jxFbm(vec2(uv.x * 2.6 + iTime * 0.015, 5.0));
    float mist = band * (0.45 + 0.55 * mistN) * 0.085 * GW_DENSITY;
    effect += vec3(0.55, 0.66, 0.84) * mist;

    // ------------------------------------------------------------------
    // THE LONE BOAT / FIGURE — one dim warm ember low-center, the solitary
    // point of life. Rendered small: a soft warm glow over a faint short
    // hull-smear, swaying almost imperceptibly on the cold water. A whisper
    // of warm reflection trails just beneath it. No tall pole — the earlier
    // version's long hairline read as a streetlamp, which broke the 意境.
    // ------------------------------------------------------------------
    float swayX = sin(mod(iTime, 41.0) * 0.5) * 0.006     // slow primary sway
                + sin(mod(iTime, 17.0) * 1.3) * 0.0025;   // tiny secondary rock
    float bobY  = sin(mod(iTime, 23.0) * 0.7) * 0.0035;   // gentle vertical bob
    vec2 boatPos = vec2(0.5 + swayX, 0.32 + bobY);

    // Aspect-corrected distance to the ember.
    vec2 bd = (uv - boatPos) * vec2(aspect, 1.0);

    // Soft warm glow — small and dim, the lamp under the straw cloak.
    float flick = 0.88 + 0.12 * sin(mod(iTime, 13.0) * 2.1);
    float core  = smoothstep(0.014 * GW_GLOW, 0.0, length(bd));     // tiny bright heart
    float glow  = smoothstep(0.060 * GW_GLOW, 0.0, length(bd)) * 0.40;
    vec3 amber  = vec3(1.0, 0.74, 0.42);                  // #ffbc6b ember
    effect += amber * (core * 0.55 + glow) * flick;

    // Faint short hull: a low, wide, very dim warm smear just under the glow,
    // so the ember reads as a BOAT carrying a light, not a free-floating dot.
    vec2 hd = (uv - vec2(boatPos.x, boatPos.y - 0.018)) * vec2(aspect, 1.0);
    hd.x *= 0.42;                                         // wide horizontally
    hd.y *= 2.4;                                          // thin vertically
    float hull = smoothstep(0.060, 0.0, length(hd)) * 0.16;
    effect += vec3(0.85, 0.66, 0.46) * hull;

    // A whisper of warm reflection on the river just beneath, smeared
    // vertically (cold black water catching the one warm point). Subtle, and
    // it fades downward so it never becomes a pole.
    vec2 rd = (uv - vec2(boatPos.x, boatPos.y - 0.045)) * vec2(aspect, 1.0);
    rd.y *= 0.30;                                          // vertical smear
    float refl = smoothstep(0.05, 0.0, length(rd)) * 0.10;
    refl *= smoothstep(boatPos.y, boatPos.y - 0.10, uv.y); // only just below
    effect += vec3(0.95, 0.72, 0.45) * refl;

    // ------------------------------------------------------------------
    // Composite (mandatory): additive, luminous-on-dark; text legible.
    // ------------------------------------------------------------------
    effect = max(effect, 0.0);

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (snow, mist, and the
    // ember alike) so the feeling reads at a glance — cold/bleak (-1) through the
    // authored pewter (0) to warm/tender (+1). Default 0 = identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;

    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
