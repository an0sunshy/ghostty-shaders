// 登鸛雀樓 (Dēng Guànquè Lóu) — Climbing Stork Tower — 王之渙 (Wang Zhihuan), Tang
//   白日依山盡，黃河入海流。
//   欲窮千里目，更上一層樓。
//   "The pale sun sinks against the mountains and is spent;
//    the Yellow River pours on toward the distant sea.
//    To see a thousand li, climb one more storey."
//
// One commanding, elevated PANORAMA seen from high on the tower — distance
// itself is the subject. The whole frame is organised around a single shared
// horizon (uv.y ≈ 0.58) spanning the full width: the keystone where both the
// sun/mountains AND the river's far end meet. The camera looks slightly DOWN
// over a vast plain.
//
//   - Sky (above the horizon): indigo dusk, the top ~40% kept near
//     iBackgroundColor (留白) so terminal glyphs read cleanly.
//   - 白日依山盡 : a dark mountain-range silhouette sits ON the horizon, massed
//     in the RIGHT third and dipping low to the left. A soft white-gold sun
//     disc rests on the right-side ridge and eases almost imperceptibly DOWN
//     behind it over a long loop (secondary motion — the sun "leaning on the
//     mountains and spent").
//   - 黃河入海流 : the Yellow River is a broad band filling the LOWER third,
//     crossing roughly horizontally — WIDE and BRIGHT near the bottom edge,
//     NARROWING and converging to a vanishing point ON the horizon (just LEFT
//     of the sun), where it melts into a pale sea-haze glow (入海). True
//     perspective recession, not a tilted slash.
//   - LEAD motion: specular current-glints are born near the viewer (bottom)
//     and travel DOWNSTREAM, receding UP toward the sea-haze vanishing point
//     (into the distance). A near layer (brighter/faster/warmer) and a far
//     layer (dimmer/slower/cooler) give the water parallax depth.
//
// DEPTH NOTE (this house is ADDITIVE luminance on a BLACK plane, so atmospheric
// perspective is INVERTED): distance means LESS added light toward black, never
// haze toward white — otherwise distant water would brighten the text region.
// So the river is dimmer + cooler + lower-contrast toward the horizon, glints
// BUNCH (perspective) but FADE toward the vanishing point, and a soft low
// vignette only REMOVES light (留白-safe).
//
// Palette: dusty-gold river #d5ae49, pale sea-haze #c9daf8, white-gold sun
//          #fef1d1, indigo dusk #0a1024, mountain #06070c.
//
// Four "feeling" dials (GW_MOOD / GW_ENERGY / GW_DENSITY / GW_GLOW, neutral at
// their defaults) let one set of controls retune the scene: MOOD warms/cools
// the whole dusk, ENERGY drives the river-glint agitation, DENSITY the river +
// glint fill vs the sky 留白, GLOW the bloom radii of the sun/haze/glints.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls. In THIS panorama:
//   MOOD    tints the whole dusk warm/cool (golden sunset .. cold twilight);
//   ENERGY  scales the river current-glint agitation (still water .. churn);
//   DENSITY scales the river/glint fill vs the dark sky 留白 (sparse .. lush);
//   GLOW    scales the bloom radii (sun corona, sea-haze, glints: crisp .. dreamy).
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

// --- hash / value-noise / fbm (house style; inlined, defined before use) ---

float dgHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float dgNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = dgHash(i);
    float b = dgHash(i + vec2(1.0, 0.0));
    float c = dgHash(i + vec2(0.0, 1.0));
    float d = dgHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float dgFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * dgNoise(p); p *= 2.05; a *= 0.5; }
    return v;
}

// Soft round point glow in aspect-corrected space. Returns 0..1.
float dgGlow(vec2 p, vec2 c, float r) {
    float d = length(p - c);
    return exp(-d * d / max(r * r, 1e-4));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                 // host is top-origin: uv.y = 1 at top

    // Sample the terminal glyph layer with the UNFLIPPED coord.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // Aspect-correct so the sun disc stays round on any window shape.
    float aspect = iResolution.x / iResolution.y;
    vec2 ap = vec2(uv.x * aspect, uv.y);   // aspected position

    // Seamless looping clock. Never feed raw iTime to fast oscillators. The
    // river current / glint travel runs on a 90s loop; the sun's sink and the
    // haze breath use their own mod() inline below.
    float tFlow = mod(iTime, 90.0);
    float scroll = tFlow * (1.0 / 90.0);   // 0..1 seamless

    vec3 effect = vec3(0.0);

    // =====================================================================
    // THE KEYSTONE — one shared horizon spanning the full width
    // =====================================================================
    // Both the sun/mountains and the river's vanishing point meet at this
    // line. The river recedes UP to it; the ridge silhouette sits ON it.
    float horizon = 0.58;
    // Vanishing point for the river: on the horizon, LEFT of the sun column.
    float vanishX = 0.40;
    // Sun column, right third.
    float sunX = 0.78;

    // =====================================================================
    // 黃河入海流 — the Yellow River, a broad band receding to a sea-haze VP
    // =====================================================================
    // The band crosses roughly horizontally in the lower third. We build a
    // perspective `depth` from vertical position: 0 at the near bottom edge,
    // 1 at the horizon. The river's lateral half-width converges from WIDE
    // (near) to a pinhole AT the vanishing point, and its lateral CENTRE
    // slides from frame-centre toward vanishX as depth→1. Glints bunch toward
    // the horizon (persp) but are graded dimmer/cooler/lower-contrast there.
    {
        // depth: 0 at the bottom edge of the river plane, 1 at the horizon.
        // The river plane occupies uv.y in [0 .. horizon]; normalise within it.
        float depth = clamp(uv.y / horizon, 0.0, 1.0);
        // Only shade where we're below the horizon (the ground plane).
        float ground = smoothstep(horizon + 0.012, horizon - 0.012, uv.y);

        if (ground > 0.0) {
            // Perspective gain: foreshortening bunches detail toward the
            // horizon. 1 near the viewer, large as depth→1.
            float persp = 1.0 / max(1.02 - depth, 0.04);

            // Lateral convergence: the river centre eases from mid-frame
            // toward the vanishing point as it recedes; half-width pinches.
            float cx = mix(0.52, vanishX, depth);          // centre, in uv.x
            float halfW = mix(0.30, 0.012, depth);         // wide → pinhole
            // Measure lateral offset from the receding centreline, aspected.
            float off = (uv.x - cx) * aspect;
            float aHalfW = halfW * aspect;

            // Soft-edged band cross-section across the (converging) river.
            float band = smoothstep(aHalfW, aHalfW * 0.32, abs(off));
            // Normalised cross-band coordinate (-1 edge .. 0 centre .. 1 edge).
            float across = off / max(aHalfW, 1e-4);

            // Depth grade: the river is dimmer + cooler + lower-contrast toward
            // the horizon (inverted aerial perspective — distance → less light).
            float bright = mix(1.0, 0.35, depth);

            // Base water body: dusty gold, modulated by a slow large-scale fbm
            // sampled in moving coordinates so the surface isn't a flat ribbon.
            // The streamwise axis uses persp so texture compresses with distance.
            float bodyTex = dgFbm(vec2(depth * 5.0 * persp - scroll * 4.0,
                                       across * 2.2 + 3.0));
            bodyTex = 0.60 + 0.5 * bodyTex;
            vec3 riverWarm = vec3(0.835, 0.682, 0.286);   // dusty gold #d5ae49
            vec3 riverCool = vec3(0.560, 0.610, 0.720);   // cooled toward haze
            vec3 riverCol = mix(riverWarm, riverCool, depth * 0.8);
            // GW_DENSITY: scale how much luminous water FILLS the lower frame vs
            // leaves the dark plain in 留白 — >1 a lusher, broader river, <1 a
            // thinner, sparser flow. Default 1.0 keeps the authored coverage.
            effect += riverCol * band * bodyTex * bright * 0.32 * GW_DENSITY * ground;

            // -- travelling current-glints : specular crests on a moving flow --
            // Glints are BORN near the viewer (depth small) and travel
            // DOWNSTREAM, receding UP toward the vanishing point (depth → 1).
            // Phase advances with `scroll` so crests slide into the distance.
            // Two layers stacked for parallax depth on the water.
            //
            // GW_ENERGY scales the glint AGITATION (specular amplitude), NOT the
            // flow rate — dialing it reads as still water <-> churning current
            // instead of the glints teleporting to new positions (which scaling
            // `scroll` would cause). `eAmp` is 1.0 at the default; above default a
            // shared extra shimmer grows in to lift the crests further toward foam.
            float eAmp = 0.45 + 0.55 * GW_ENERGY;                   // 1.0 at default
            float eBoost = max(GW_ENERGY - 1.0, 0.0);              // 0 at/below default

            // Flow distortion: a perpendicular fbm in moving coords so flecks
            // weave across the current instead of marching in a clean line.
            float flow = dgFbm(vec2(depth * 6.0 - scroll * 5.0,
                                    across * 3.0 + 8.0));

            // Confine glints to the band core; fade as the river narrows.
            float glintBand = smoothstep(0.92, 0.10, abs(across));
            // Glints intensify out of the near water, then vanish exactly at
            // the haze so they don't speckle the sky / horizon seam.
            float glintAlong = smoothstep(0.02, 0.30, depth)
                             * smoothstep(1.0, 0.84, depth);

            // (a) NEAR layer — brighter, faster, warmer. Crests bunch via persp
            // so they crowd toward the horizon (perspective recession).
            float n1 = sin((depth * 30.0 * persp - scroll * 150.0) + flow * 7.0);
            float n2 = sin((depth * 41.0 * persp - scroll * 205.0) + flow * 11.0 + 2.1);
            float nearCrest = 0.55 * n1 + 0.45 * n2;                 // -1..1
            float nearGate = smoothstep(0.74, 0.96, nearCrest * 0.5 + 0.5);
            // Near glints live mostly in the foreground; fade with distance.
            float nearDepth = smoothstep(0.85, 0.05, depth);
            vec3 nearCol = vec3(1.0, 0.93, 0.66);       // warm specular
            // ENERGY: scale specular amplitude (eAmp) + an above-default churn that
            // widens the bright crests; default leaves both exactly as authored.
            float nearAmp = eAmp * (1.0 + 0.6 * eBoost);
            effect += nearCol * nearGate * glintBand * glintAlong
                            * nearDepth * 1.05 * nearAmp * GW_DENSITY * ground;

            // (b) FAR layer — dimmer, slower, cooler. Coarser, softer gate; it
            // gives the receding water a slow rolling shimmer that reads as
            // distance. Strongest in the mid/far band, dies at the haze.
            float fr1 = sin((depth * 18.0 * persp - scroll * 70.0) + flow * 5.0);
            float farGate = smoothstep(0.62, 0.93, fr1 * 0.5 + 0.5);
            float farDepth = smoothstep(0.10, 0.70, depth)
                           * smoothstep(0.98, 0.82, depth);
            vec3 farCol = vec3(0.70, 0.78, 0.92);       // cool distant specular
            effect += farCol * farGate * glintBand * glintAlong
                            * farDepth * 0.30 * eAmp * GW_DENSITY * ground;
        }

        // -- 入海 : the sea-haze glow at the vanishing point on the horizon ---
        // A soft cool bloom where the river spends itself into the distant sea,
        // sitting AT (vanishX, horizon). Pale blue-silver, with a very slow
        // breathing shimmer. It fuses the river's far end into the horizon.
        vec2 vanishC = vec2(vanishX * aspect, horizon);
        float haze = dgGlow(ap, vanishC, 0.16 * GW_GLOW);   // GW_GLOW: softer/dreamier bloom
        // Flatten the haze vertically a touch so it pools along the horizon
        // rather than blooming up into the sky / text region.
        float hazeSky = 1.0 - 0.55 * smoothstep(horizon, horizon + 0.10, uv.y);
        float hazeBreath = 0.82 + 0.18 * sin(mod(iTime, 37.0) * 0.21);
        vec3 hazeCol = vec3(0.788, 0.855, 0.973);   // pale sea-haze #c9daf8
        effect += hazeCol * haze * hazeSky * hazeBreath * 0.30;
        // A brighter pale core right at the river mouth, biased a hair BELOW
        // the horizon so it fuses with the river end, not the sky.
        vec2 mouthC = vec2(vanishX * aspect, horizon - 0.018);
        float hazeCore = dgGlow(ap, mouthC, 0.060 * GW_GLOW);
        effect += mix(hazeCol, vec3(1.0), 0.45) * hazeCore * 0.34;
    }

    // =====================================================================
    // 白日依山盡 — the white sun spent upon the mountains (right third)
    // =====================================================================
    // A dark range silhouette sits ON the shared horizon, massed in the right
    // third and dipping low to the left. The white-gold sun rests on the
    // right-side ridge, easing imperceptibly DOWN behind it over the loop.
    {
        float rx = uv.x;
        // Ridge profile measured ABOVE the horizon. Tallest in the right third,
        // dipping toward the left so the mass is asymmetric (留白 on the left).
        float rightMass = smoothstep(0.30, 0.95, rx);   // 0 left .. 1 right
        float ridgeRise = 0.085 * rightMass
                        + 0.045 * dgFbm(vec2(rx * 5.0 + 20.0, 2.0)) * rightMass
                        + 0.020 * sin(rx * 9.0 + 1.3) * rightMass;
        // Ridge top, on/above the shared horizon. Left side barely lifts off it.
        float ridge = horizon + ridgeRise;

        // Sun sinks slowly: centre eases DOWNWARD over the loop, settling so
        // its lower half is occluded by the ridge. cos ramp = seamless. The
        // ridge varies with rx, so evaluate the crest height under the sun
        // COLUMN and rest the disc on it (the radius ≈ 0.052, so a small +offset
        // keeps the disc half-touching the crest as it sinks behind the range).
        float sinkPhase = mod(iTime, 600.0) * (6.2831853 / 600.0);
        float ridgeAtSun = horizon
                         + 0.085
                         + 0.045 * dgFbm(vec2(sunX * 5.0 + 20.0, 2.0))
                         + 0.020 * sin(sunX * 9.0 + 1.3);
        float sunY = ridgeAtSun + 0.030 + 0.022 * (0.5 + 0.5 * cos(sinkPhase));
        vec2 sunC = vec2(sunX * aspect, sunY);

        // Sun disc + corona in aspect space (round).
        float dSun = length(ap - sunC);
        // GW_GLOW widens the disc edge feather and the halo radii so the sun goes
        // from a crisp disc (<1) to a hazy bloom (>1); default keeps it as authored.
        float discEdge = 0.012 * GW_GLOW;               // authored feather = 0.052-0.040
        float disc  = smoothstep(0.040 + discEdge, 0.040, dSun);  // crisp warm disc
        float coreH = smoothstep(0.030 * GW_GLOW, 0.0, dSun);     // hot centre
        float corona = dgGlow(ap, sunC, 0.16 * GW_GLOW) * 0.55;   // soft halo
        // Wide low atmospheric flush hugging the ridge where the sun meets the
        // mountains — kept to the right so it never washes the centre/text.
        float ridgeFlush = dgGlow(ap, vec2(sunX * aspect, ridgeAtSun - 0.02), 0.24 * GW_GLOW)
                         * smoothstep(0.42, 0.95, rx);

        vec3 sunCol  = vec3(0.996, 0.945, 0.820);   // white-gold #fef1d1
        vec3 sunCore = vec3(1.0, 0.985, 0.93);
        vec3 flushCol = vec3(0.78, 0.50, 0.30);     // warm dusk flush

        // The mountain silhouette OCCLUDES whatever is behind/below the ridge:
        // 1 above the ridge (sky), 0 below (dark mountain near iBackgroundColor).
        float aboveRidge = smoothstep(ridge - 0.006, ridge + 0.006, uv.y);
        float sky = aboveRidge;

        // Sun light only contributes in the sky; the disc's lower half is thus
        // naturally cut by the ridge crest (依山盡).
        effect += sunCol * disc * 0.95 * sky;
        effect += sunCore * coreH * 0.55 * sky;
        effect += sunCol * corona * sky;
        effect += flushCol * ridgeFlush * sky * 0.5;

        // A thin warm rim-light along the ridge crest right under the sun, so
        // the mountain edge catches the last light. Hair-width, near the column.
        float rimBand = smoothstep(0.012, 0.0, abs(uv.y - ridge));
        float nearSun = smoothstep(0.34, 0.0, abs(uv.x - sunX));
        effect += vec3(0.95, 0.62, 0.32) * rimBand * nearSun * 0.22;
    }

    // =====================================================================
    // Indigo dusk sky tint + soft low vignette (both 留白-safe)
    // =====================================================================
    // A whisper of indigo above the horizon gives the dusk its colour without
    // lifting the text region much; it fades to nothing toward the top so the
    // upper ~40% stays clear.
    {
        float skyBand = smoothstep(horizon - 0.02, horizon + 0.06, uv.y)
                      * smoothstep(1.0, 0.62, uv.y);     // dies toward the top
        vec3 indigo = vec3(0.039, 0.063, 0.141);         // indigo dusk #0a1024
        effect += indigo * skyBand * 0.16;
    }

    // Soft low vignette — only REMOVES light, so it deepens the dark centre and
    // corners (留白-safe). Strongest at the edges and toward the bottom corners.
    {
        vec2 c = uv - vec2(0.5, 0.5);
        float vig = 1.0 - smoothstep(0.35, 0.95, length(vec2(c.x * 1.1, c.y * 1.3)));
        vig = mix(0.78, 1.0, vig);          // never fully black out
        effect *= vig;
    }

    // ---- MANDATORY composite : additive, luminous-on-dark, text legible ----
    effect = max(effect, vec3(0.0));

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (river, sun, haze,
    // and indigo sky alike) so the feeling reads at a glance — cold/twilight
    // (-1) through the authored dusk (0) to warm/golden sunset (+1). Default
    // 0 = identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;
    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
