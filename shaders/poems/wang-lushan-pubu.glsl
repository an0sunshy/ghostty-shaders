// 望廬山瀑布 (Wàng Lúshān Pùbù) — Gazing at the Lushan Waterfall — Li Bai
//   飛流直下三千尺，疑是銀河落九天。
//   "The torrent plunges straight down three thousand feet —
//    as if the Milky Way were falling from heaven."
//
// One bright vertical ribbon of white water plunges straight DOWN a
// near-black mountain face. The water core is cold silver-white, textured
// by downward-scrolling fBm so the column streams continuously DOWNWARD
// (verify across frames: bright filaments slide toward the BOTTOM as iTime
// grows). Where the fall strikes its basin the column bursts into spray
// that disperses and settles at the BASE. At the very summit a small,
// tightly contained violet bloom (the 香爐峰 incense-burner peak mist)
// breathes and lifts in quiet counter-motion. The frame stays dark and
// open left and right of the single fall — heavy 留白 for the glyphs, and
// NO full-frame color wash (the effect starts at black and adds only
// luminous focal water/spray/haze).
//
// Float-safety: the column's downward streaming is a seamless fract() drift
// (safe for arbitrarily large iTime); every sin/cos oscillation is fed a
// mod(iTime, period) phase so nothing degrades as iTime grows.
//
// Four shared "feeling" dials (neutral at their defaults — all-default is the
// authored look): GW_MOOD warms/cools the whole scene; GW_ENERGY scales the
// motion AGITATION (spray splash drift + haze breath/lift amplitude, not the
// stream rate); GW_DENSITY scales fill vs 留白 (spray droplet keep-threshold +
// column/haze coverage); GW_GLOW scales bloom/softness (column feather, spray
// fan, basin mist, and summit-haze radii).

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

// ---- hash / value-noise / fbm (inlined, house style) ----------------------
float wfHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float wfNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = wfHash(i);
    float b = wfHash(i + vec2(1.0, 0.0));
    float c = wfHash(i + vec2(0.0, 1.0));
    float d = wfHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 4-octave fbm — enough detail for streaking water strands.
float wfFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * wfNoise(p);
        p *= 2.03;
        a *= 0.5;
    }
    return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                       // host top-origin: uv.y=1 TOP, uv.y=0 BOTTOM

    // Text layer sampled with the UNFLIPPED coordinate.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    float aspect = iResolution.x / iResolution.y;

    // The fall occupies a narrow vertical band right of center, leaving the
    // left two-thirds open for terminal text (busiest on the left). x measured
    // from the band axis, aspect-corrected so the column width is honest at any
    // window shape. Every spatial element below — column, spray, basin mist,
    // and summit haze — derives from xb/ax, so this single axis moves the whole
    // fall together.
    float axis = 0.66;
    float xb = (uv.x - axis) * aspect;        // signed distance from axis
    float ax = abs(xb);

    // Vertical layout of the single fall. uv.y: 1 = TOP of screen, 0 = BOTTOM.
    //   summit  ~0.92 (TOP)    — water issues from the cliff lip
    //   plunge   0.18 .. 0.92  — the continuous streaming column
    //   basin   ~0.16 (BOTTOM) — water strikes the rocks and bursts into spray
    // The water therefore plunges from a high source toward the bottom of the
    // frame, exactly as the eye should read a falling torrent.
    float summit = 0.92;
    float basin  = 0.16;

    // ---- the water column ---------------------------------------------------
    // Bright dense core, feathered shoulders. The column is full only between
    // the summit lip and the basin; it fades in just below the lip and tapers
    // out as it dives into the spray at the base.
    // GW_GLOW widens the soft shoulders so the column reads dreamier (or crisper
    // below 1). The dense inner-stream edge and the outer veil both scale.
    float core    = smoothstep(0.085 * GW_GLOW, 0.0,  ax);   // dense inner stream
    float feather = smoothstep(0.155 * GW_GLOW, 0.02, ax);   // softer outer veil
    // topFade: appear just below the summit lip (uv.y a little under summit).
    float topFade = smoothstep(summit + 0.04, summit - 0.10, uv.y);
    // botFade: dissolve into the basin spray near the bottom.
    float botFade = smoothstep(basin - 0.04, basin + 0.14, uv.y);
    float colBody = topFade * botFade;

    // Downward streaming: the filaments must move toward the BOTTOM (toward
    // uv.y = 0) as iTime grows. A translation toward -uv.y means the noise
    // sample's y-coordinate must INCREASE with time, so we ADD the scroll to
    // uv.y*freq. Seamless continuous drift via fract() (period ~5.9s) so it
    // never feeds raw iTime to the fbm and never degrades at large iTime.
    float scroll = fract(iTime * 0.17);          // 0..1, loops
    // Layered, strongly Y-stretched fbm at different rates → fast water
    // filaments sliding over slower bulk flow. High Y frequency reads as thin
    // vertical streaks, never blocky cells. The PLUS sign on scroll makes the
    // strands descend.
    vec2 q1 = vec2(xb * 11.0, uv.y * 9.0  + scroll * 16.0);
    vec2 q2 = vec2(xb * 19.0, uv.y * 17.0 + scroll * 30.0 + 19.0);
    vec2 q3 = vec2(xb * 31.0, uv.y * 30.0 + scroll * 52.0 + 41.0);
    float strands = wfFbm(q1) * 0.55 + wfFbm(q2) * 0.40 + wfFbm(q3) * 0.22;
    strands = smoothstep(0.40, 1.05, strands);   // lift into bright filaments

    // Column brightness: bright core threaded with brighter strands, gated by
    // the horizontal feather and the vertical body window.
    float water = (core * (0.55 + 0.55 * strands) + feather * 0.16) * colBody;

    // ---- spray bursting at the BASE -----------------------------------------
    // Where the fall strikes its rocks (LOW on screen, small uv.y) it explodes
    // into a cloud of droplets that fan OUTWARD and lift slightly, then settle.
    // This impact burst is the bright focal event at the BOTTOM — it gives the
    // whole column its downward-plunge reading. The spray field is gated to a
    // band centered on the basin so it can never appear near the summit.
    float basinBand = smoothstep(basin + 0.20, basin, uv.y)         // ramp down to basin
                    * smoothstep(basin - 0.18, basin + 0.02, uv.y); // taper below basin
    // Spray fans WIDER than the column right at the impact, then settles in.
    float depth = clamp(((basin + 0.20) - uv.y) / 0.26, 0.0, 1.0);
    float sprayWidth = smoothstep((0.16 + depth * 0.20) * GW_GLOW, 0.0, ax);
    // Fine cellular droplet grid (high frequency so droplets stay small and
    // pointlike). The grid drifts gently outward from the impact line — the
    // visible "splash" — on a wrapped phase; per-cell hash drives placement
    // and a wrapped twinkle.
    float sprayT = mod(iTime, 240.0);
    vec2  sg  = vec2(xb * 60.0, uv.y * 66.0 + sprayT * 5.0);  // splash drift
    vec2  sc  = floor(sg);
    vec2  sfp = fract(sg);
    float sh  = wfHash(sc);
    vec2  dpos = vec2(fract(sh * 21.3), fract(sh * 47.9));
    float dd = length(sfp - dpos);
    // GW_DENSITY lowers the per-cell keep-threshold so MORE droplets survive
    // (lusher splash) or fewer for sparser 留白. The droplet radius also scales
    // with GW_GLOW so glow=1/density=1 stays exactly the authored splash.
    float sprayThresh = clamp(0.55 - (GW_DENSITY - 1.0) * 0.22, 0.05, 0.95);
    float droplet = smoothstep(0.34 * GW_GLOW, 0.0, dd) * step(sprayThresh, sh);
    // GW_ENERGY scales the splash AGITATION amplitude — the depth of each
    // droplet's twinkle swing — NOT the oscillation rate, so dialing it reads
    // as a calmer<->livelier spray rather than droplets jumping phase. Default
    // (1.0) keeps the authored 0.5±0.5 pulse exactly.
    float eAmp = 0.45 + 0.55 * GW_ENERGY;                 // 1.0 at default
    float pulse = 0.5 + 0.5 * eAmp * sin(sprayT * (1.3 + sh * 3.0) + sh * 6.2831);
    float spray = droplet * pulse * sprayWidth * basinBand * 1.15;
    // A soft diffuse mist glow pooled tightly at the basin, fading fast so it
    // never washes the lower frame. Narrow in x, short in y, brightest right
    // at the impact line.
    float impact = smoothstep(basin + 0.10, basin - 0.02, uv.y)
                 * smoothstep(basin - 0.14, basin - 0.02, uv.y);
    float mist = impact * smoothstep(0.20 * GW_GLOW, 0.0, ax) * 0.40;

    // ---- summit violet haze (香爐峰) ----------------------------------------
    // A SMALL, tightly contained purple-magenta bloom at the cliff lip (TOP)
    // that breathes and lifts UPWARD — quiet counter-motion to the falling
    // water. A smooth gaussian (NO dotty fbm grain — that earlier read as
    // upward emission), anchored at the summit so it stays a soft focal glow
    // rather than a frame-wide wash.
    float hazeT = mod(iTime, 180.0);
    // GW_ENERGY scales the bloom's breath/lift AGITATION amplitude (how much it
    // rises and pulses), NOT the breath rate — calm<->lively without the bloom
    // jumping. Default keeps the authored 0.018 lift and 0.38 breathe swing.
    float hazeAmp = 0.45 + 0.55 * GW_ENERGY;       // 1.0 at default (reuses eAmp form)
    // Compact radius in both axes; the y-center lifts a touch (toward +uv.y =
    // up) on a slow wrapped breath so the bloom appears to rise.
    float hazeLift = 0.018 * hazeAmp * sin(hazeT * 0.16);
    // GW_GLOW widens the gaussian (softer, dreamier bloom) by shrinking the hp
    // scale; glow=1 leaves the authored 4.2 / 6.4 radii unchanged.
    float hazeGlowR = 1.0 / GW_GLOW;
    vec2  hp = vec2(xb * 4.2 * hazeGlowR, (uv.y - (summit + 0.03) - hazeLift) * 6.4 * hazeGlowR);
    float hazeBlob = exp(-dot(hp, hp) * 1.7);      // tight, smooth radial bloom
    float breathe = 0.62 + 0.38 * hazeAmp * sin(hazeT * 0.21);
    float haze = hazeBlob * breathe;

    // ---- compose colors -----------------------------------------------------
    // Cold silver-white water core; a cooler blue in the feathered veil and
    // spray; a contained violet-magenta for the summit mist.
    vec3 waterCol  = vec3(0.874, 0.913, 1.0);     // #dfe9ff
    vec3 veilCol   = vec3(0.62,  0.70,  0.92);     // cooler blue veil
    vec3 sprayCol  = vec3(0.80,  0.86,  1.0);
    vec3 hazeCol   = vec3(0.541, 0.388, 0.808);   // #8a63ce violet mist
    vec3 hazeHot   = vec3(0.74,  0.46,  0.86);     // magenta-leaning highlight

    vec3 effect = vec3(0.0);
    // Water: bright core in silver-white, shoulders tinted cooler.
    effect += waterCol * water * 0.82;
    effect += veilCol  * feather * colBody * 0.09;
    // Spray + basin mist (contained around the base).
    effect += sprayCol * spray * 0.55;
    effect += sprayCol * mist  * 0.42;
    // Summit haze, magenta core where densest — tightly contained.
    effect += mix(hazeCol, hazeHot, hazeBlob) * haze * 0.38;

    // Guard every channel non-negative (additive, luminous-on-dark).
    effect = max(effect, vec3(0.0));

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (water, spray, basin
    // mist, and the violet summit haze alike) so the feeling reads at a glance —
    // cold/bleak (-1) through the authored silver-violet (0) to warm/tender (+1).
    // Default 0 = identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;

    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}