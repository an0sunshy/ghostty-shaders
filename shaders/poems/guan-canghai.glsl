// 觀滄海 (Guān Cānghǎi) — Gazing at the Vast Sea — 曹操 (Cáo Cāo), Han 樂府
//   秋風蕭瑟，洪波湧起。日月之行，若出其中。
//   "The autumn wind sighs and moans; mighty billows surge and rise.
//    The sun and moon in their courses seem to issue from within this sea."
//
// The whole open-sea plane heaves as one body. From back to front:
//   - Upper third: bare near-black sky, heavy 留白 so terminal text reads.
//   - At a flat far horizon (uv.y≈0.62) a faint warm-to-silver glow breathes
//     on a long cycle (日月之行 — sun/moon issuing from the sea).
//   - Lower two-thirds: a deep slate-teal sea built from summed low-frequency
//     swell-bands. Broad rolling crests scroll from the horizon DOWN toward
//     the viewer (洪波湧起) — verified: crest pattern advances to the BOTTOM
//     of the frame as iTime increases. Wavelength grows and amplitude lifts
//     in perspective as the water nears the viewer.
//   - A slow global wind-envelope sine raises and lowers the overall swell
//     amplitude (秋風蕭瑟 — the autumn wind gusting and easing).
//   - Cool crest-silver glints slide along the swell crests where the surface
//     tilts up to catch the cold light.
// Nothing breaks; no foam, no spray, no boat — the sea itself is the subject.
//
// Palette: deep slate-teal sea #0a2630 → #11403c, crest-silver #c9daf8,
//          faint horizon glow #fef1d1, near-black sky #04080b.
//
// Four "feeling" dials tune the scene (neutral defaults reproduce this look):
//   GW_MOOD   warm/cool global tone · GW_ENERGY  wind-gust agitation (storminess)
//   GW_DENSITY glow + crest-light fill vs 留白 · GW_GLOW  horizon-glow/seam bloom.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls. In this scene:
//   MOOD   — global warm/cool tone over sky-glow, sea, and crest-silver alike.
//   ENERGY — swell agitation: the autumn-wind gust amplitude (and an extra
//            choppiness above default), NOT the roll rate (no teleporting waves).
//   DENSITY— how much light fills the void: horizon-glow strength + crest-glint
//            coverage vs heavier 留白 of bare dark sea and sky.
//   GLOW   — bloom/softness of the 日月之行 horizon glow and the waterline seam.
#ifndef GW_MOOD
#define GW_MOOD 0.0      // palette warmth: -1 cold/blue .. 0 neutral .. +1 warm
#endif
#ifndef GW_ENERGY
#define GW_ENERGY 1.0    // motion: 0.3 still/glassy .. 1 .. 2 stormy
#endif
#ifndef GW_DENSITY
#define GW_DENSITY 1.0   // fill vs 留白: 0.3 sparse/empty .. 1 .. 1.8 luminous
#endif
#ifndef GW_GLOW
#define GW_GLOW 1.0      // bloom/softness: 0.6 crisp .. 1 .. 2.5 dreamy
#endif

// --- hash / value-noise / fbm (house style; defined before use) ---

float gcHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float gcNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = gcHash(i);
    float b = gcHash(i + vec2(1.0, 0.0));
    float c = gcHash(i + vec2(0.0, 1.0));
    float d = gcHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float gcFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * gcNoise(p); p *= 2.04; a *= 0.5; }
    return v;
}

// Swell height field at a sea-plane position. `sp` is the perspective sea
// coordinate (sp.x across, sp.y = distance from horizon, increasing toward
// the viewer). `t` is a seamless looping clock. Returns a signed height in
// roughly [-1, 1]: the summed low-frequency swell bands plus a slow fbm
// roughness, all scrolling toward the viewer (sp.y increasing over time → the
// same crest sits at larger sp.y later → it moves toward the bottom).
float swellHeight(vec2 sp, float t) {
    // Three incommensurate swell bands, long wavelengths, scrolling in +sp.y
    // (toward the viewer / bottom). Phases per band keep them from aligning.
    float h = 0.0;
    h += 0.55 * sin(sp.y *  6.0 + sp.x * 0.7  - t * 0.90);
    h += 0.32 * sin(sp.y *  9.5 - sp.x * 1.1  - t * 1.30 + 1.7);
    h += 0.18 * sin(sp.y * 15.0 + sp.x * 1.9  - t * 1.80 + 3.9);
    // Slow large-scale fbm roughness travelling with the swell so the crest
    // lines aren't perfectly straight — the sea breathes as one rough body.
    float rough = gcFbm(vec2(sp.x * 1.3, sp.y * 2.2 - t * 0.35)) - 0.5;
    h += rough * 0.5;
    return h * 0.5;   // keep within ~[-1,1]
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                 // host is top-origin: uv.y = 1 at top

    // Sample the terminal glyph layer with the UNFLIPPED coord.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // Aspect-correct so swell wavelengths read evenly across any window shape.
    float aspect = iResolution.x / iResolution.y;
    float ax = (uv.x - 0.5) * aspect;  // centered, aspect-corrected x

    // Seamless looping clocks. Never feed raw iTime to fast oscillators.
    float tRoll = mod(iTime, 62.831853);   // swell roll (≈ 10 wave periods)
    float tWind = mod(iTime, 120.0);        // slow wind-envelope gusting
    float tGlow = mod(iTime, 90.0);         // horizon glow breathing

    vec3 effect = vec3(0.0);

    // ---- geometry: flat far horizon; sea fills the lower two-thirds ----
    float horizon = 0.62;                    // sea below, sky above
    // Waterline seam: GW_GLOW softens the feather (wider transition) so the
    // horizon edge melts more for dreamier glow; default 1.0 keeps ±0.02.
    float seam = 0.02 * GW_GLOW;
    float sea = smoothstep(horizon + seam, horizon - seam, uv.y);  // 1 in water

    // 秋風蕭瑟 : a slow global wind-envelope that swells and eases the whole
    // sea's amplitude — the autumn wind gusting. Long seamless cycle, gentle.
    // GW_ENERGY scales the gust DEPTH (agitation amplitude) about its mean, not
    // the gust RATE — so the dial reads as glassy-calm <-> stormy wind rather
    // than the swell pattern speeding up or teleporting. Default (1.0) keeps the
    // authored 0.22 swing; an extra choppiness is added ONLY above default.
    float eAmp = 0.45 + 0.55 * GW_ENERGY;                          // 1.0 at default
    float wind = 0.78 + 0.22 * eAmp * sin(tWind * (6.2831853 / 120.0));

    if (sea > 0.0) {
        // Perspective sea coordinate. depth = 0 at horizon, grows toward the
        // viewer (bottom). Map screen y below the horizon into a depth that
        // compresses near the horizon and expands near the viewer, so swell
        // wavelength visibly lengthens as the water approaches — open-ocean
        // perspective. pow guarded per portability rules.
        float below = clamp((horizon - uv.y) / horizon, 0.0, 1.0);
        float depth = pow(max(below, 1e-4), 0.62);   // 0 (far) .. ~1 (near)

        // Sea coordinate fed to the swell field. The x term spreads with depth
        // so crests fan slightly toward the viewer (perspective convergence).
        vec2 sp = vec2(ax * (0.6 + 0.8 * depth), depth * 3.2);

        // Height and its along-depth slope (finite difference) → the surface
        // tilt that decides which faces catch the cold crest light.
        float h  = swellHeight(sp, tRoll) * wind;
        float h2 = swellHeight(sp + vec2(0.0, 0.06), tRoll) * wind;
        float slope = (h2 - h) / 0.06;     // d(height)/d(depth toward viewer)

        // Base water color: deep slate-teal, slightly greener / lighter as it
        // nears the viewer (more light penetrates the near water).
        vec3 deep = vec3(0.039, 0.149, 0.188);   // #0a2630
        vec3 near = vec3(0.067, 0.251, 0.235);   // #11403c
        vec3 water = mix(deep, near, depth);

        // Swell shading: crest faces tilted toward the (cold, high) light are
        // lifted; troughs sink darker. `h` modulates brightness directly so
        // the whole plane reads as rolling relief, not a flat smear. The
        // relief contrast strengthens toward the viewer (near swells are read
        // more sharply than the compressed far ones) and rides the wind gust.
        float relief = 0.5 + 0.5 * h;            // 0 trough .. 1 crest
        // Above default, deepen the crest-to-trough relief contrast so the sea
        // reads choppier/stormier (the gust biting harder); grows ONLY for
        // GW_ENERGY>1 so the default plane is untouched.
        float reliefGain = (0.42 + 0.55 * depth) * wind
                         * (1.0 + 0.45 * max(GW_ENERGY - 1.0, 0.0) * depth);
        water *= 0.50 + reliefGain * relief;

        // Cool crest-silver glints: where a crest is high AND its up-slope
        // faces the light (slope < 0 on the viewer-facing side), the surface
        // catches a sharp cold rim. Thin band near the crest tops only.
        float crest = smoothstep(0.45, 0.95, relief);
        float facing = smoothstep(0.0, -1.4, slope);   // viewer-facing rise
        float glint = crest * facing;
        // A faint shimmer travels along crests so glints slide, not blink.
        float slide = 0.6 + 0.4 * sin(sp.x * 5.0 - tRoll * 1.1 + sp.y * 2.0);
        vec3 silver = vec3(0.788, 0.855, 0.973);  // crest-silver #c9daf8
        // Glints fade toward the horizon (distance) and ride the wind envelope.
        // GW_DENSITY scales how much crest-light fills the sea surface: >1 strews
        // more silver over the swells (lush), <1 leaves more dark water (留白).
        water += silver * glint * slide * 0.5 * depth * wind * GW_DENSITY;

        // Feather the very top edge of the sea into the horizon seam so the
        // waterline isn't a hard cut.
        effect += water * sea;
    }

    // ---- 日月之行 : a faint warm-to-silver glow breathing at the horizon ----
    // A low, wide, soft band hugging the horizon seam — light seeming to issue
    // from within the sea. Warm core easing to silver at the edges; it pulses
    // almost imperceptibly on a long cycle. Centered, kept dim so the center
    // text stays readable; concentrated at the seam, not washed over the sky.
    {
        float glowBreath = 0.70 + 0.30 * sin(tGlow * (6.2831853 / 90.0));
        // Vertical falloff: tight to the horizon, a touch more above (in sky)
        // than below so it reads as rising out of the water. GW_GLOW widens the
        // falloff (smaller rate = larger soft halo) so >1 reads dreamier, <1
        // crisper; default 1.0 keeps the authored 26 / 16 rates exactly.
        float dy = uv.y - horizon;
        float vUp   = exp(-max(dy, 0.0)  * (26.0 / GW_GLOW));   // into the sky
        float vDown = exp(-max(-dy, 0.0) * (16.0 / GW_GLOW));   // into the water
        float vband = max(vUp, vDown);
        // Horizontal falloff: a broad swell of light centered on the frame,
        // brightest at center, fading to the margins (heroic oceanic breadth).
        // GW_GLOW also broadens this wing-spread for a softer, wider glow.
        float hband = exp(-ax * ax * (1.8 / GW_GLOW));
        float g = vband * hband * glowBreath;
        // Warm core (#fef1d1) blending to cold silver toward the wings.
        vec3 warm   = vec3(0.996, 0.945, 0.820);    // #fef1d1
        vec3 cool   = vec3(0.788, 0.855, 0.973);    // #c9daf8
        vec3 glowCol = mix(cool, warm, hband);
        // GW_DENSITY scales the glow strength (how much the 日月之行 light fills
        // the void vs leaving bare dark sky); default 1.0 = authored 0.30.
        effect += glowCol * g * 0.30 * GW_DENSITY;
    }

    // ---- MANDATORY composite : additive, luminous-on-dark, text legible ----
    effect = max(effect, vec3(0.0));

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (sky-glow, sea, and
    // crest-silver alike) so the feeling reads at a glance — cold/bleak (-1)
    // through the authored slate-teal (0) to warm/tender (+1). Default 0 =
    // identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;
    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}