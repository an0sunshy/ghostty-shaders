// 使至塞上 (Shǐ Zhì Sàishàng) — On a Mission to the Frontier, Wang Wei
//   大漠孤煙直，長河落日圓。
//   "Over the vast desert a lone smoke-column rises straight;
//    on the long river the setting sun hangs round."
//
// The whole frontier reduced to two pure forms standing on emptiness:
//   1. 孤煙直 — a single near-perfectly-vertical thread of beacon smoke on
//      the left third, rising slowly with a faint heat-haze wobble. Amber at
//      its root, fading to cold ash as it climbs into the windless sky.
//   2. 落日圓 — a huge round low sun resting on the horizon at lower-right,
//      sinking almost imperceptibly over a multi-minute loop, its specular
//      glitter laid as a horizontal shimmer band across the 長河 (long river)
//      below it.
//
// Maximal 留白: the sky and the entire center stay near-black for text. All
// light is concentrated in the two primitives and the thin river band.
//
// Palette: ember orange #ff8c42, dusty gold #d5ae49, deep indigo #0a1024,
// charcoal #06070c.
//
// Four "feeling" dials tune the scene from one set of controls (all-default
// reproduces the authored look): GW_MOOD warms/cools the whole frame, GW_ENERGY
// drives the smoke's heat-haze sway and river-shimmer drift, GW_DENSITY fills
// (dusk band / river glints / smoke opacity) vs 留白, GW_GLOW softens the sun
// bloom, beacon fire, and smoke feathering.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls.
//   GW_MOOD    palette warmth: -1 cold/blue .. 0 neutral .. +1 warm (global tint)
//   GW_ENERGY  motion agitation: 0.3 still .. 1 .. 2 lively — heat-haze wobble of
//              the smoke column and the river-shimmer drift (amplitudes, not rates)
//   GW_DENSITY fill vs 留白: 0.3 sparse .. 1 .. 1.8 lush — dusk band, river glint
//              coverage, and smoke filament opacity
//   GW_GLOW    bloom/softness: 0.6 crisp .. 1 .. 2.5 dreamy — sun bloom, beacon
//              fire halo, and smoke-column feather widths
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

float frHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 2D value noise + 4-octave fbm — used for the smoke filament's internal
// turbulence and the river shimmer. Standard smoothstep-interpolated lattice.
float frNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = frHash(i);
    float b = frHash(i + vec2(1.0, 0.0));
    float c = frHash(i + vec2(0.0, 1.0));
    float d = frHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float frFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * frNoise(p); p *= 2.03; a *= 0.5; }
    return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                 // host top-origin: uv.y = 1 at top

    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    float aspect = iResolution.x / iResolution.y;

    // Seamless loop clocks — never feed raw iTime to sin/cos/fract.
    float tSlow  = mod(iTime, 360.0);   // sun's multi-minute descent
    float tHaze  = mod(iTime, 40.0);    // smoke heat-haze wobble
    float tRise  = mod(iTime, 24.0);    // upward scroll of smoke turbulence
    float tRiver = mod(iTime, 18.0);    // river shimmer travel

    vec3 effect = vec3(0.0);

    // GW_ENERGY scales motion AGITATION (sway/shimmer AMPLITUDE), never the
    // oscillator rates — dialing it reads as calm<->lively air, not elements
    // teleporting. eAmp = 1.0 at the default so the authored motion is exact.
    float eAmp = 0.45 + 0.55 * GW_ENERGY;            // 1.0 at default
    float eGust = max(GW_ENERGY - 1.0, 0.0);         // extra agitation only above default

    // ---- Horizon: where desert (charcoal) meets the indigo dusk sky -------
    // A single low line; the river sits just below it, the sun rests on it.
    float horizon = 0.300;
    // Faint warm dusk band hugging the horizon (the desert glow at sunset),
    // strongest at the right under the sun, fading left and upward. Kept low
    // so it never washes the center.
    float duskBand = smoothstep(0.16, horizon, uv.y) * smoothstep(0.46, horizon, uv.y);
    float duskRight = smoothstep(0.15, 0.85, uv.x);
    // GW_DENSITY scales the dusk fill — lusher warm wash or sparser 留白.
    effect += vec3(0.20, 0.10, 0.045) * duskBand * (0.25 + 0.55 * duskRight) * GW_DENSITY;

    // ---- 落日圓 : the round setting sun, lower-right --------------------------
    // Sinks imperceptibly: its center eases down toward the horizon across the
    // 360s loop, resting partly on it. Aspect-corrected so the disk is round.
    float sunSink = 0.018 * (0.5 - 0.5 * cos(tSlow * 6.2831853 / 360.0));
    vec2 sunPos = vec2(0.735, horizon + 0.052 - sunSink);
    float sunR = 0.115;
    vec2 sd = (uv - sunPos) * vec2(aspect, 1.0);
    float sdist = length(sd);

    // Solid disc with a soft feathered limb. The huge low sun of the frontier.
    float disc = smoothstep(sunR, sunR * 0.86, sdist);
    // Warm vertical gradient inside the disc: brighter molten gold at the top
    // edge, deeper ember toward the base where it meets the haze.
    float discGrad = smoothstep(-sunR, sunR, sd.y);
    vec3 sunCore = mix(vec3(1.00, 0.45, 0.16),   // ember base  #ff7329-ish
                       vec3(1.00, 0.74, 0.34),   // molten gold top
                       discGrad);
    effect += sunCore * disc * 1.05;

    // Soft outer bloom — the only large glow, but kept to the lower-right and
    // falling off fast so the upper sky and center stay dark. GW_GLOW widens the
    // bloom radius (divide the falloff rate) for a softer, dreamier halo.
    float bloom = exp(-max(sdist - sunR, 0.0) * (7.5 / GW_GLOW)) * (1.0 - disc);
    effect += vec3(0.95, 0.42, 0.16) * bloom * 0.55;

    // ---- 長河 : the long river — a thin horizontal shimmer band below the sun -
    // A narrow band just under the horizon carrying the sun's reflection as
    // travelling specular glints. Brightest directly beneath the sun, thinning
    // outward along its length.
    float bandCenter = horizon - 0.045;
    // GW_GLOW softens the band's vertical feather (wider, dreamier reflection).
    float bandHalf   = 0.030 * GW_GLOW;
    float band = smoothstep(bandHalf, 0.0, abs(uv.y - bandCenter));
    // Reflection is anchored under the sun and decays with horizontal distance.
    float alongRiver = exp(-pow(max(abs(uv.x - sunPos.x), 1e-4), 1.3) * 6.0);
    // Travelling ripple-normal field: glints pop where the wave field crosses
    // a threshold, and the whole pattern drifts so highlights march outward.
    // GW_ENERGY adds a gentle extra lateral sway to the field (amplitude only,
    // above default) so a livelier river chops more; the base drift is unchanged.
    float rippleSway = sin(mod(iTime, 21.0) * 6.2831853 / 21.0 + uv.x * 8.0) * 0.6 * eGust;
    float ripple = frFbm(vec2(uv.x * 26.0 - tRiver * 0.9 + rippleSway, uv.y * 60.0 + tRiver * 0.4));
    // GW_DENSITY widens the glint band (lower the pop threshold) for more sparkle
    // coverage, or narrows it for a sparser river. Default keeps the authored band.
    float glintLo = clamp(0.62 - (GW_DENSITY - 1.0) * 0.18, 0.05, 0.95);
    float glint = smoothstep(glintLo, 0.80, ripple);
    vec3 riverCol = mix(vec3(0.85, 0.40, 0.16), vec3(0.84, 0.69, 0.30), discGrad);
    effect += riverCol * band * alongRiver * (0.18 + 0.95 * glint);

    // ---- 孤煙直 : the lone vertical beacon-smoke column, left third ----------
    // A single straight luminous filament rising from the desert. Its lateral
    // position wobbles by only a few percent (windless air, heat-haze only).
    float smokeX = 0.255;
    // Vertical extent: from just above the horizon up into the high sky.
    float baseY = horizon + 0.005;
    float topY  = 0.965;
    float col = smoothstep(baseY, baseY + 0.02, uv.y) * smoothstep(topY, topY - 0.22, uv.y);

    // Height parameter 0 at root → 1 near the top, for widening + fade.
    float h = clamp((uv.y - baseY) / (topY - baseY), 0.0, 1.0);

    // Heat-haze wobble: tiny near the root, growing slightly with height; two
    // slow sines on the loop clock plus a noise nudge. Amplitude stays small
    // so the column reads as 直 (straight). GW_ENERGY scales this wobble's
    // AMPLITUDE (eAmp) — calm air barely shimmers, lively air bends the thread
    // more — and adds a slow extra gust only above default. Rates are untouched.
    float wob = sin(uv.y * 11.0 - tHaze * 6.2831853 / 40.0) * 0.006
              + sin(uv.y * 23.0 + tHaze * 6.2831853 / 40.0 * 1.7) * 0.0028;
    wob *= eAmp;
    wob += sin(uv.y * 6.0 - mod(iTime, 37.0) * 6.2831853 / 37.0) * 0.006 * eGust;
    wob *= (0.25 + 0.95 * h);                       // root anchored, top sways
    // Upward-scrolling internal turbulence so the smoke visibly rises.
    float turb = frFbm(vec2(uv.y * 7.0 - tRise * 6.2831853 / 24.0 * 1.4, uv.x * 5.0));
    wob += (turb - 0.5) * 0.010 * h * eAmp;

    float cx = (uv.x - (smokeX + wob)) * aspect;     // aspect-correct width
    // Column half-width: tight thread at the root, feathering wider as it
    // dissipates upward. Kept narrow so the column reads as 直 — a thin
    // straight thread, not a torch plume. GW_GLOW softens the feather (a wider,
    // dreamier thread); default keeps the authored width.
    float halfW = (0.0075 + 0.026 * h) * GW_GLOW;
    float colShape = exp(-pow(max(abs(cx), 1e-4), 2.0) / (halfW * halfW));

    // Density falls off toward the top (smoke thinning into windless sky) and
    // is broken up by the rising turbulence for a living, wispy filament.
    // GW_DENSITY scales the column's overall opacity — a lusher plume or a
    // fainter wisp into 留白; default leaves the authored density.
    float density = colShape * col * GW_DENSITY;
    density *= mix(1.0, 0.35, h);                    // thin out with height
    density *= (0.55 + 0.65 * turb);                 // wispy internal breakup

    // Color: warm ember at the root → dusty gold → cold ash as it climbs.
    // The high ash is a NEUTRAL warm grey (taupe), NOT a blue-grey: the old
    // bluish ash made the mid-column read faintly green where the gold→ash mix
    // crossed. Smoke against an indigo dusk should stay an ashen taupe, never
    // pick up a green/teal cast.
    vec3 smokeCol = mix(vec3(1.00, 0.55, 0.20),      // ember root  #ff8c42
                        vec3(0.80, 0.66, 0.34),      // dusty gold  ~#d5ae49
                        smoothstep(0.0, 0.4, h));
    smokeCol = mix(smokeCol, vec3(0.52, 0.50, 0.46), // cold ashen taupe, high up
                   smoothstep(0.30, 0.95, h));
    // Read as 煙 (smoke), not a torch flame: keep the column dimmer than the
    // fire root so the eye reads a rising thread, not a flare.
    effect += smokeCol * density * 0.70;

    // A small warm glow at the smoke's root (the beacon fire on the desert).
    // Tightened so it stays a compact ember rather than a broad torch flare.
    // GW_GLOW widens the ember halo (divide the squared falloff rate).
    vec2 fd = (uv - vec2(smokeX, baseY)) * vec2(aspect, 1.0);
    float fire = exp(-dot(fd, fd) * (520.0 / (GW_GLOW * GW_GLOW)));
    effect += vec3(1.00, 0.52, 0.18) * fire * 0.5;

    effect = max(effect, 0.0);

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (sun, river, smoke,
    // and dusk alike) so the feeling reads at a glance — cold/bleak (-1) through
    // the authored dusk (0) to warm/tender (+1). Default 0 = identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;

    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
