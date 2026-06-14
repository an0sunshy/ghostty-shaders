// 春江花月夜 (Chūn Jiāng Huā Yuè Yè) — Spring River, Flower, Moon, Night
//   張若虛 (Zhāng Ruòxū), Tang
//   春江潮水連海平，海上明月共潮生。灩灩隨波千萬里。
//   "The spring river's tide is level with the sea; over the sea a bright moon
//    is born with the tide. Its glittering light follows the waves ten thousand li."
//
// Eye-level across tide-filled water. The scene composites, back to front:
//   - Upper sky (above uv.y≈0.62): black-violet night, bare 留白 for text.
//   - At the flat far horizon a faint warm ember line marks sea meeting sky.
//   - Just above the horizon a large, calm, WHOLE moon disc rises a few percent
//     over a long loop, wrapped in a soft cool bloom halo (海上明月).
//   - Below the horizon the MOONGLINT ROAD: a true reflective mirror-path, not
//     a field of dots. A perspective water plane carries a few long, soft,
//     slightly-curved horizontal ripple bands marching toward the viewer; a
//     signed ripple-height field and its slope decide which up-faces tilt to
//     catch the moon, and glints IGNITE on those crest faces. The road is a
//     vertical wedge widening from the moon's column down to the bottom edge,
//     brightest on-column and dissolving to dark water at the L/R margins
//     (灩灩隨波 — the shimmer following the waves).
//   - Two glint layers give depth: a NEAR layer (brighter, faster, warm-white)
//     and a FAR layer (dimmer, slower, cooler). Additive-on-black inverts
//     aerial perspective, so the road is graded DIMMER and COOLER toward the
//     horizon — distance is less light, never haze toward white.
//   - A soft low vignette removes light at the bottom corners only.
// The dark left & right thirds of the water and the upper sky stay clear so
// terminal glyphs read cleanly.
//
// Palette: sky black-violet #0b0a1e, glint silver-white #eef4ff,
//          moon cool-white #dfe6ff, warm horizon ember #2a1c22.
// Additive, luminous-on-dark; every channel non-negative.
//
// Four "feeling" dials tune the mood without changing the composition:
// GW_MOOD warms/cools the whole scene, GW_ENERGY agitates the glint shimmer,
// GW_DENSITY makes the moonglint road lusher or sparser, and GW_GLOW softens or
// crisps the moon halo and road bloom. All defaults reproduce the authored look.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls.
//   GW_MOOD    — global warm/cool tone over moon, road, and horizon ember.
//   GW_ENERGY  — agitation of the moonglint shimmer (sway amplitude, not rate).
//   GW_DENSITY — how lush the glint road reads: more vs fewer crests ignited.
//   GW_GLOW    — bloom/softness of the moon halo, road column, and specular root.
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

// --- hash / value-noise / fbm (house style; defined before use) ---

float cjHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float cjNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = cjHash(i);
    float b = cjHash(i + vec2(1.0, 0.0));
    float c = cjHash(i + vec2(0.0, 1.0));
    float d = cjHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float cjFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * cjNoise(p); p = p * 2.03 + 5.1; a *= 0.5; }
    return v;
}

// Signed ripple-height of the reflective water at a perspective coordinate.
// `wp.x` runs across the road, `wp.y` is distance-from-horizon growing toward
// the viewer; `t` is a seamless looping clock. A few long, incommensurate
// horizontal swell bands scroll in +wp.y (toward the viewer / bottom), lightly
// bent across x and roughened by a slow drifting fbm so the crest lines curve
// rather than ruling straight across. Returns roughly [-1, 1].
float cjRipple(vec2 wp, float t) {
    float h = 0.0;
    h += 0.60 * sin(wp.y *  7.0 + sin(wp.x * 0.8) * 0.9 - t * 1.05);
    h += 0.30 * sin(wp.y * 12.5 - sin(wp.x * 1.3 + 1.7) * 0.7 - t * 1.55 + 2.1);
    h += 0.16 * sin(wp.y * 21.0 + sin(wp.x * 2.1 + 3.3) * 0.5 - t * 2.20 + 4.4);
    float rough = cjFbm(vec2(wp.x * 1.6, wp.y * 2.6 - t * 0.30)) - 0.5;
    h += rough * 0.55;
    return h * 0.5;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                 // host is top-origin: uv.y = 1 at top

    // Sample the terminal glyph layer with the UNFLIPPED coord.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // Aspect-correct so the moon stays round and the road reads evenly.
    float aspect = iResolution.x / iResolution.y;
    float ax = (uv.x - 0.5) * aspect;  // centered, aspect-corrected x
    float cx = 0.5;

    // Seamless looping clocks. Never feed raw iTime to fast oscillators.
    float tRise = mod(iTime, 240.0);   // very slow moon rise
    float tNear = mod(iTime, 75.398);  // near road ripple roll (~12 periods)
    float tFar  = mod(iTime, 113.10);  // far road ripple roll (slower)
    float tGlow = mod(iTime, 90.0);    // horizon ember breathing

    // Geometry: flat far horizon raised to eye-level. Water below, sky above.
    float horizon = 0.62;
    // Moon eases up a few percent over the long loop, seated just above the seam.
    float rise = smoothstep(0.0, 1.0, 0.5 - 0.5 * cos(tRise * (6.2831853 / 240.0)));
    float moonY = horizon + 0.052 + 0.030 * rise;

    vec3 effect = vec3(0.0);

    // ---- 海上明月 : the moon — large, calm, whole, just above the horizon ----
    // Round in aspect space; crisp body, soft cool bloom halo. A faint fbm
    // mottle keeps the disc from reading as a flat sticker. The moon is the one
    // light source the whole road reflects, so it stays centered and steady.
    float R = 0.080;
    vec2 mp = vec2(ax, uv.y - moonY);
    float md = length(mp) / R;
    float body = smoothstep(1.0, 0.82, md);
    // GW_GLOW widens the cool bloom halo around the disc (the body edge stays put,
    // so default is identity): a larger radius softens the exp falloff and pushes
    // the outer smoothstep cutoff out, letting the moon breathe a dreamier corona.
    float halo = exp(-max(md - 1.0, 0.0) * (2.3 / GW_GLOW))
               * smoothstep(1.0 + 2.0 * GW_GLOW, 0.95, md);
    {
        float mottle = cjFbm(mp * 4.0 + 5.0);
        vec3 moonCore = vec3(0.874, 0.902, 1.0) * (0.92 + 0.08 * mottle);  // #dfe6ff
        vec3 haloCol  = vec3(0.62, 0.66, 0.88);
        effect += moonCore * body + haloCol * halo * 0.50;
    }

    // ---- 灩灩隨波 : the MOONGLINT ROAD — a true reflective mirror-path ----
    // Only the water region below the horizon reads the ripple field, so the
    // entire sky half skips the fbm-bearing height samples (lossless gate).
    float water = smoothstep(horizon + 0.012, horizon - 0.012, uv.y);  // 1 below
    if (water > 0.0) {
        // Perspective water coordinate. `below` is 0 at the horizon, growing
        // toward the viewer (bottom). pow compresses ripples near the horizon
        // and lengthens them toward the viewer — water receding to a flat sea.
        float below = clamp((horizon - uv.y) / horizon, 0.0, 1.0);
        float depth = pow(max(below, 1e-4), 0.62);          // 0 far .. ~1 near

        // The road is a vertical wedge: a Gaussian column centered on the moon
        // that WIDENS toward the viewer, so the bright path fans from the moon's
        // narrow column at the seam to a broad glittering base at the bottom.
        // GW_GLOW scales the column's soft half-width so the road blooms softer
        // (dreamier spread) or crisper. Default 1.0 keeps the authored wedge.
        float colWidth = (0.045 + 0.30 * depth) * GW_GLOW;
        float column = exp(-(ax * ax) / (colWidth * colWidth));

        // GW_ENERGY scales the AGITATION of the glint shimmer — how strongly each
        // crest's light pulses as it slides — NOT the slide RATE, so dialing it
        // reads as a calmer or livelier surface rather than glints teleporting.
        // eAmp = 1.0 at the default; a small extra wobble grows only above default.
        float eAmp  = 0.45 + 0.55 * GW_ENERGY;              // 1.0 at default
        float eGust = max(GW_ENERGY - 1.0, 0.0);            // 0 at/below default

        // Aerial perspective (inverted for additive): the road is graded dimmer
        // toward the horizon and brighter toward the viewer. Never hazes white.
        float grade = 0.30 + 0.70 * depth;

        // Across-road x spreads with depth so crests fan toward the viewer.
        float wx = ax * (0.7 + 0.9 * depth);

        // --- NEAR glint layer: brighter, faster, warm-white, sharper crests ---
        vec2 wpN  = vec2(wx, depth * 3.4);
        float hN  = cjRipple(wpN, tNear);
        float hN2 = cjRipple(wpN + vec2(0.0, 0.05), tNear);
        float slopeN = (hN2 - hN) / 0.05;                   // tilt toward viewer
        float reliefN = 0.5 + 0.5 * hN;                     // 0 trough .. 1 crest
        // GW_DENSITY lowers the crest-ignition threshold so MORE wave faces catch
        // the moon (a lusher, fuller glitter road) or raises it for sparser 留白.
        // The threshold floats with the dial; default 1.0 keeps the authored 0.52.
        float crestLoN = clamp(0.52 - (GW_DENSITY - 1.0) * 0.22, 0.10, 0.95);
        float crestN  = smoothstep(crestLoN, 0.98, reliefN);
        float faceN   = smoothstep(0.0, -1.5, slopeN);      // up-face catches moon
        // A shimmer travels along the crest so glints slide toward the viewer
        // rather than blink in place — light walking down the water. eAmp scales
        // the pulse depth (agitation); eGust adds a slow cross-road swell above
        // default. The slide RATE (tNear) is untouched so glints never teleport.
        float slideN  = 0.55 + 0.45 * eAmp * sin(wpN.x * 5.0 - tNear * 1.25 + wpN.y * 2.2)
                      + 0.18 * eGust * sin(wpN.y * 1.7 - tNear * 0.7 + wpN.x * 1.1);
        float glintN  = crestN * faceN * clamp(slideN, 0.0, 1.6);
        vec3  colN    = vec3(0.933, 0.957, 1.0);            // warm silver-white #eef4ff

        // --- FAR glint layer: dimmer, slower, cooler, finer ripples ---
        vec2 wpF  = vec2(wx * 1.6 + 2.7, depth * 5.6);
        float hF  = cjRipple(wpF, tFar);
        float hF2 = cjRipple(wpF + vec2(0.0, 0.05), tFar);
        float slopeF = (hF2 - hF) / 0.05;
        float reliefF = 0.5 + 0.5 * hF;
        float crestLoF = clamp(0.55 - (GW_DENSITY - 1.0) * 0.22, 0.10, 0.95);
        float crestF  = smoothstep(crestLoF, 0.98, reliefF);
        float faceF   = smoothstep(0.0, -1.5, slopeF);
        float slideF  = 0.55 + 0.45 * eAmp * sin(wpF.x * 6.0 - tFar * 0.9 + wpF.y * 2.0)
                      + 0.18 * eGust * sin(wpF.y * 1.5 - tFar * 0.55 + wpF.x * 1.3);
        float glintF  = crestF * faceF * clamp(slideF, 0.0, 1.6);
        vec3  colF    = vec3(0.78, 0.84, 1.0);              // cooler blue-silver

        // The road brightens a touch as the moon climbs higher over the water.
        float roadGain = 0.85 + 0.30 * rise;

        // Combine: near layer leads (brighter), far layer fills behind it. Both
        // ride the column wedge and the inverted-perspective grade. A whisper of
        // base sheen on-column seats the glints on lit water, not on black.
        vec3 glints = colN * glintN * 1.70 + colF * glintF * 0.90 * (0.4 + 0.6 * (1.0 - depth));
        float sheen = column * grade * 0.06;
        // A soft specular root right under the moon bridges the disc to the road
        // so the silver path reads as one continuous column from the moon down,
        // not a gap then ripples. Strongest at the seam, fading into the water.
        float root = exp(-(ax * ax) / ((0.030 + 0.05 * depth) * GW_GLOW))
                   * smoothstep(0.16, 0.0, below) * roadGain;
        vec3 road = (glints * column * grade * roadGain
                     + vec3(0.36, 0.42, 0.62) * sheen
                     + vec3(0.80, 0.86, 1.0) * root * 0.16) * water;
        effect += road;
    }

    // ---- warm ember horizon line (海平) : sea meeting sky ----
    // A thin warm seam centered on-column, breathing on a long cycle. Kept dim
    // and narrow so the upper sky and the dark margins stay clear for text.
    {
        float seam = exp(-abs(uv.y - horizon) * 150.0);
        float seamCol = exp(-(ax * ax) / 0.14);
        float breath = 0.78 + 0.22 * sin(tGlow * (6.2831853 / 90.0));
        vec3 ember = vec3(0.165, 0.110, 0.133);   // warm horizon ember #2a1c22
        effect += ember * seam * seamCol * breath;
    }

    // ---- soft low vignette : removes light at the bottom corners only ----
    // Multiplicative dim that only darkens the lower L/R, deepening the 留白 of
    // the dark water margins without lifting any pixel toward white.
    {
        float vign = 1.0 - 0.30 * smoothstep(0.45, 1.0, abs(ax)) * smoothstep(0.5, 0.0, uv.y);
        effect *= clamp(vign, 0.0, 1.0);
    }

    // ---- MANDATORY composite : additive, luminous-on-dark, text legible ----
    effect = max(effect, vec3(0.0));

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (moon, glint road, and
    // horizon ember alike) so the feeling reads at a glance — cold/bleak (-1)
    // through the authored cool silver (0) to warm/tender (+1). Default 0 = identity.
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;
    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
