// Night Snow (夜雪) — Bai Juyi: "夜深知雪重，時聞折竹聲"
// "Deep in the night I know the snow is heavy — now and then I hear
//  bamboo snap."
//
// A dark room lit only from outside: a soft cool-white paper window whose
// glow swells almost imperceptibly over a multi-minute cycle as snow piles
// up unseen (雪重). No falling snow is drawn — only the cold luminous wash.
// Down one edge run faint jade bamboo lines; on a long randomized timer one
// culm bows under accumulating weight, then RELEASES with a brief bright
// shudder that rings up the stalk — the 折竹聲 (the snap of bamboo) made
// visual. Otherwise: stillness, and maximal 留白 so terminal text sits in
// the dark.
//
// Palette: black #04050a room, moon-white #e6eeff window, jade #3a5a48 edge.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls. In this scene: MOOD warms/cools the
// paper-window glow and jade culms; ENERGY scales the culms' air-sway and the
// frost-grain drift amplitude (still <-> breezy); DENSITY scales how much the
// window fills the room (pane + bloom + bamboo presence) vs 留白; GLOW scales
// the window bloom, pane feather and culm soft edges (crisp <-> dreamy).
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

// ---------------------------------------------------------------------------
// hash / value-noise / fbm — inlined per house style (clear-night.glsl).
// ---------------------------------------------------------------------------
float yxHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float yxNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = yxHash(i);
    float b = yxHash(i + vec2(1.0, 0.0));
    float c = yxHash(i + vec2(0.0, 1.0));
    float d = yxHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float yxFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * yxNoise(p); p *= 2.07; a *= 0.5; }
    return v;
}

// Signed distance to an axis-aligned rounded box centred at the origin.
// b = half-extents, rad = corner radius. Negative inside, positive outside.
float yxRoundBox(vec2 p, vec2 b, float rad) {
    vec2 d = abs(p) - b + rad;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - rad;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                       // host top-origin: uv.y=1 top

    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    float aspect = iResolution.x / iResolution.y;

    // -----------------------------------------------------------------------
    // Paper window — a soft-edged rounded rectangle, upper-left of centre so
    // the screen's middle/lower body stays open for text. Coordinates are
    // aspect-corrected (multiply x by aspect) so the window reads as a true
    // rectangle, not stretched, on any window shape.
    // -----------------------------------------------------------------------
    vec2 winCenter = vec2(0.30, 0.36);
    vec2 p = (uv - winCenter) * vec2(aspect, 1.0);
    vec2 halfSize = vec2(0.150, 0.180);      // paper pane half-extents
    float corner = 0.022;

    float sd = yxRoundBox(p, halfSize, corner);

    // Lattice (paper-screen muntins): a faint darker grid inside the pane so
    // it reads as a 紙窗 rather than a blank slab. Static; very subtle.
    float gx = abs(fract((p.x + halfSize.x) / 0.075) - 0.5);
    float gy = abs(fract((p.y + halfSize.y) / 0.075) - 0.5);
    float lattice = smoothstep(0.45, 0.5, max(gx, gy)) * 0.18;

    // Snow-glow breathing: a long, almost imperceptible swell — snow piling
    // up outside deepens the diffuse light through the paper. Period 240s,
    // wrapped so huge iTime never blows up the sin (FLOAT-SAFETY). Range
    // 0.62 -> 1.0 so the window is always faintly lit but visibly deepens.
    float tBreath = mod(iTime, 240.0) / 240.0;        // 0..1
    float breathe = 0.62 + 0.38 * (0.5 - 0.5 * cos(tBreath * 6.2831853));

    // The pane fill: bright flat interior fading softly at the rounded edge,
    // plus a wider outer bloom that bleeds the cold light into the room.
    // GW_GLOW widens the soft inner feather and the outer halo radius (divide
    // the falloff rate by GW_GLOW) so >1 = dreamy bleed, <1 = crisp edge.
    float pane = smoothstep(0.012 * GW_GLOW, -0.030 * GW_GLOW, sd); // soft inner falloff
    float bloom = exp(max(sd, 0.0) * (-7.0 / GW_GLOW)) * 0.55;      // halo outside the pane

    // Faint fBm "frost-grain" texture drifting slowly across the paper so the
    // glow isn't a dead flat wash — feathered, organic, like light scattered
    // through rice paper with snow beyond. Drift is slow continuous motion.
    vec2 grainUV = p * 6.0 + vec2(mod(iTime, 600.0) * 0.010, mod(iTime, 600.0) * 0.004);
    float grain = yxFbm(grainUV);
    float paperTex = 0.80 + 0.32 * grain;             // 0.80..1.12 modulation

    // Window contribution. Interior = textured pane minus lattice; the bloom
    // is added everywhere (gated by distance) so it lifts the room edge.
    // GW_DENSITY scales how much the window FILLS the room (vs 留白): it lifts
    // the bloom that bleeds light into the surrounding dark — >1 lusher/lit,
    // <1 sparser/emptier. Default 1.0 leaves the authored coverage exactly.
    float windowLight = pane * paperTex * (1.0 - lattice) + bloom * GW_DENSITY;
    windowLight *= breathe;

    vec3 windowColor = vec3(0.902, 0.933, 1.000);     // moon-white #e6eeff

    // -----------------------------------------------------------------------
    // Bamboo — faint jade culms down the RIGHT edge, silhouetted against the
    // dark room (so they sit away from the window and the central text). One
    // chosen culm slowly bows under snow weight, then snaps back with a brief
    // bright shudder on a long randomized timer: the 折竹聲 made visible.
    // -----------------------------------------------------------------------
    // Event clock: each snap cycle lasts SNAP_PERIOD seconds. A wrapped time
    // and an integer event index (derived without feeding raw iTime to a fast
    // fract) randomize which culm snaps and how deeply it bows.
    const float SNAP_PERIOD = 18.0;
    float tWrap = mod(iTime, SNAP_PERIOD * 64.0);     // bounded, long loop
    float evF = floor(tWrap / SNAP_PERIOD);           // event index 0..63
    float local = (tWrap - evF * SNAP_PERIOD) / SNAP_PERIOD; // 0..1 within event

    // Per-event randoms.
    float eh = yxHash(vec2(evF, 7.0));
    float whichCulm = floor(eh * 3.0);                // 0,1,2 — which bows
    float bowDepth = 0.018 + 0.020 * fract(eh * 13.7);

    // Envelope across the event. The break happens at local = BREAK.
    //  - load: a slow bow that grows through the loading phase (snow piling)
    //  - release: the bow lets go sharply at the break
    //  - shudder: a damped ring AFTER the break, used to flick + flash the
    //             stalk. Built so it is identically zero before the break
    //             (no step(0.0,·) edge artefact — the culm stays faint jade
    //             for the whole loading phase, and only the snap is bright).
    const float BREAK = 0.78;
    float load = smoothstep(0.0, BREAK - 0.02, local);          // 0..1 slow bow
    float released = smoothstep(BREAK, BREAK + 0.02, local);    // 0 before, 1 after
    float bow = bowDepth * load * (1.0 - released);             // bow vanishes on snap

    // Time elapsed since the break (0 during the entire loading phase). The
    // `released` gate guarantees the shudder cannot fire before the snap.
    float since = max(local - BREAK, 0.0);
    float shudderEnv = exp(-since * 38.0) * released;           // 0 until break
    float shudder = sin(since * 90.0) * shudderEnv;             // ringing flick
    float snapFlash = shudderEnv;                               // brief bright pulse

    // GW_ENERGY scales the lead motion AGITATION — the culms' ever-present
    // air-sway AMPLITUDE (and, above default, a gentle extra breeze) — without
    // touching the oscillator RATE, so dialing it reads as still<->breezy air
    // instead of the stalks teleporting. Default (1.0) keeps the authored sway.
    float eAmp = 0.45 + 0.55 * GW_ENERGY;             // 1.0 at default
    float gust = max(GW_ENERGY - 1.0, 0.0);           // grows only above default

    float bamboo = 0.0;
    vec3 bambooColor = vec3(0.227, 0.353, 0.282);     // jade #3a5a48
    const int N_CULM = 3;
    for (int ci = 0; ci < N_CULM; ci++) {
        float fc = float(ci);
        // Culm base x along the right edge, gently spaced; aspect-corrected.
        float baseX = 0.86 + fc * 0.045;
        // Static lean + subtle ever-present sway (light air), very small.
        float sway = sin(uv.y * 5.0 + fc * 2.1 + mod(iTime, 50.0) * 0.25) * 0.004 * eAmp
                   + sin(uv.y * 3.0 + fc * 1.3 + mod(iTime, 37.0) * 0.5) * 0.004 * gust;

        // This culm's snap deflection (only the chosen one bows/shudders).
        float isThis = step(abs(fc - whichCulm), 0.5);
        float bendHere = isThis * (bow + shudder * 0.012);

        // Deflection grows toward the TOP of the stalk (cantilever: tip moves
        // most). uv.y here is top-origin, so the tip is near uv.y small.
        float tipWeight = smoothstep(0.62, 0.04, uv.y);  // 0 at base, 1 at tip
        float curveX = baseX + (sway + bendHere) * tipWeight;

        // Vertical extent of the culm: from top edge down to ~0.62.
        float colSpan = smoothstep(0.66, 0.62, uv.y);    // fade out at bottom

        // Distance from this pixel to the (curved) vertical line, in aspect-
        // corrected x so the stalk has even thickness regardless of window
        // shape. During the shudder the chosen stalk briefly thickens (a
        // glow blooming off the break) so the snap reads as a real event.
        // GW_GLOW widens the soft edge of the culm (crisp <-> bloomed).
        float dx = (uv.x - curveX) * aspect;
        float thick = 0.0045 + isThis * snapFlash * 0.0060;
        float line = smoothstep(thick * GW_GLOW, thick * 0.33, abs(dx)) * colSpan;

        // Faint node bands (bamboo joints) every ~0.16 in y.
        float node = smoothstep(0.46, 0.5, abs(fract(uv.y / 0.16) - 0.5));
        line *= (0.7 + 0.3 * node);

        // Base jade visibility is low (faint); the snapping culm flashes
        // bright cool-white along its length during the brief shudder only.
        // GW_DENSITY lifts the faint base presence of the culms (fuller edge
        // vs emptier 留白); the snap flash is left at authored strength.
        float vis = 0.16 * GW_DENSITY + isThis * snapFlash * 1.6;
        bamboo += line * vis;
    }

    // Snap flash bleeds a hair of cool-white (not pure jade) — the brief
    // brightness of the break catching the snow-light.
    vec3 snapColor = mix(bambooColor, vec3(0.85, 0.92, 1.0),
                         clamp(snapFlash, 0.0, 1.0));

    // -----------------------------------------------------------------------
    // Composite — additive, luminous-on-dark. Center/lower screen stays near
    // zero (留白) so glyphs read; light concentrates in the window + edge.
    // -----------------------------------------------------------------------
    vec3 effect = windowColor * windowLight        // the paper-window wash
                + snapColor   * bamboo;             // jade culms / the snap

    effect = max(effect, 0.0);                      // every channel >= 0

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (paper-window glow
    // and jade culms alike) so the feeling reads at a glance — cold/bleak (-1)
    // through the authored moon-white (0) to warm/tender (+1). Default 0 =
    // identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;

    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
