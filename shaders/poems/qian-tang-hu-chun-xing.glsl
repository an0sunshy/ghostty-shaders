// 錢塘湖春行 — Spring Stroll by Qiantang Lake (Bai Juyi)
//   "水面初平雲腳低 ... 亂花漸欲迷人眼"
//   The lake's face just leveled, the cloud-feet hang low; riotous blossoms
//   are about to dazzle the eye.
//
// Early spring at West Lake, held as a serene FIELD scene — no figures, no
// birds, just the water and the sky doing very little. The whole frame is
// built from three quiet layers:
//   * 水面初平 — a calm, just-level lake water band LOW in the frame: a dim
//     horizontal shimmer that ripples gently in place. This is the anchor.
//   * 雲腳低 — soft low-hanging "cloud-feet" resting just above the far
//     shore: a low horizontal mist/cloud glow, its densest mass biased to the
//     RIGHT third so the busy left text rows stay clear. Drifts slowly
//     sideways, never rising.
//   * 亂花漸欲迷人眼 — a sparse drift of luminous spring blossom-motes easing
//     DOWN across the field, the only residual figure-motion. Quiet, not a
//     particle storm; well under 10% coverage so the center 留白 stays open.
//   * 綠楊/白沙堤 — a faint, cheap shore hint: a thin pale strip of sand bank
//     under a breath of willow-green, sitting on the far water line.
//
// Everything is additive luminous-on-dark; the center stays near-zero so
// terminal text passes through cleanly (留白). The spring-dawn palette is soft
// — cool lake, warm cloud-blush, pale petals — with no harsh colors.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls. In THIS scene they drive:
//   * GW_MOOD    — global warm/cool tone over the whole field (water, cloud, petals)
//   * GW_ENERGY  — agitation of the residual motion: petal sway + a gentle drift
//                  gust (amplitudes only, never the fall RATE — petals don't teleport)
//   * GW_DENSITY — how much the frame fills: petal coverage + water/cloud/ambient lift
//   * GW_GLOW    — bloom/softness: petal size, cloud-glow radius, water band feather
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

// ---- hash / value-noise / fbm (inlined, self-contained) -------------------
float qhash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float qhash1(float n) {
    return fract(sin(n * 91.3458) * 47453.5453);
}
float qnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = qhash(i);
    float b = qhash(i + vec2(1.0, 0.0));
    float c = qhash(i + vec2(0.0, 1.0));
    float d = qhash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float qfbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * qnoise(p); p *= 2.07; a *= 0.5; }
    return v;
}

// A single soft blossom-mote centered at the origin in aspect-corrected space.
// `q` is the fragment position relative to the mote center (already aspect-
// corrected); `scale` its half-size. Returns a 0..1 coverage mask with a soft
// feathered edge — a gently squashed luminous petal-flake, brighter at the
// core, so the drift reads as 亂花 (riotous blossom) rather than abstract dots.
float qmote(vec2 q, float scale) {
    q /= max(scale, 1e-4);
    // Slight vertical squash so the flake reads as a settling petal, not a
    // perfect disc. Radial profile feathered to a soft edge at r~1.
    float r = length(q * vec2(1.0, 1.25));
    return smoothstep(1.0, 0.18, r);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                         // host is top-origin (uv.y=1 top)

    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    float aspect = iResolution.x / iResolution.y;
    // Aspect-corrected space: x widened by aspect so glows & motes stay round.
    // After the flip above, larger uv.y sits toward the TOP of the screen
    // (uv.y=1 is the very top). So P.y = uv.y - 0.5 grows UPWARD: positive
    // P.y is high sky, negative P.y is low toward the water/bottom.
    vec2 P = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);

    vec3 effect = vec3(0.0);

    // Spring-dawn palette — all soft, no harsh colors.
    vec3 waterCol = vec3(0.35, 0.55, 0.70);    // cool lake glint
    vec3 cloudCol = vec3(1.00, 0.86, 0.66);    // warm low cloud-blush
    vec3 petalCol = vec3(0.96, 0.84, 0.86);    // pale spring blossom
    vec3 sandCol  = vec3(0.90, 0.86, 0.72);    // pale white-sand bank
    vec3 willowCol = vec3(0.55, 0.74, 0.52);   // faint willow green

    // The far water line: low on screen. After the flip, larger uv.y is toward
    // the TOP, so a LOW water line needs a SMALL uv.y. Everything (water band,
    // cloud-feet, shore) is anchored to this single horizon so the scene reads
    // as one coherent lake edge, with the whole frame above it staying dark.
    float horizon = 0.22;
    float bandY = uv.y - horizon;

    // ---- 水面初平: the calm, just-level lake band (the anchor) -------------
    // A dim horizontal shimmer LOW on screen. Kept narrow and faint so it reads
    // as "water surface", not a fill — most of the frame stays pure dark above
    // it (留白). GW_GLOW widens the band's feather (dividing the falloff rate by
    // GW_GLOW^2 broadens the soft edge); 1 = authored.
    float band = exp(-bandY * bandY * 340.0 / (GW_GLOW * GW_GLOW));
    // Animated ripple texture along the band — slow continuous in-place drift.
    // The two 4-octave qfbm calls are the priciest work in the scene, but the
    // band masks them to a thin sliver around the water line; everywhere else
    // `band` is ~0 and `shimmer` would multiply the ripple out anyway. Gate the
    // noise to where the band is actually lit so the upper ~78% of the frame
    // (留白) skips it entirely — visually lossless, ~10% of frame cost recovered.
    float glint = 0.0;
    if (band > 0.002) {
        float driftT = mod(iTime, 600.0);
        float ripple  = qfbm(vec2(uv.x * 9.0 - driftT * 0.20, uv.y * 22.0 + driftT * 0.10));
        float ripple2 = qfbm(vec2(uv.x * 18.0 + driftT * 0.35, uv.y * 30.0));
        // Sparse specular glints: gate the ripple field above a threshold so
        // highlights pop and vanish as the surface gently moves in place.
        glint = smoothstep(0.66, 0.92, ripple) * smoothstep(0.55, 0.95, ripple2);
    }
    // GW_DENSITY scales how much the lake fills the frame (留白 vs lusher water).
    float shimmer = band * (0.05 + 0.50 * glint) * GW_DENSITY;
    effect += waterCol * shimmer;

    // ---- 雲腳低: low cloud-feet resting just above the far shore -----------
    // A soft, broad horizontal mist/cloud glow hugging the water line — present
    // but understated, lighting the lake's far edge. Its densest mass is biased
    // to the RIGHT third (the single bright focal point) so the busy LEFT text
    // rows stay clear. It sits a hair ABOVE the water band so the cloud-feet
    // appear to hang just over the shore, and drifts slowly SIDEWAYS (never
    // rising). A second, very dim full-width veil keeps the whole far edge soft.
    float cloudCY = horizon + 0.045;                   // just above the water line
    float cloudCX = 0.72;                              // focal mass in the right third
    float cloudDriftT = mod(iTime, 600.0);
    // Slow sideways sway of the focal mass — small, so it drifts, not slides.
    float cloudShift = sin(cloudDriftT * 0.04) * 0.05;
    float cx = (uv.x - (cloudCX + cloudShift)) * aspect;
    float cy = uv.y - cloudCY;
    // Anisotropic falloff: very wide and flat (cloud-feet stretch along the
    // shore), shallow in height. GW_GLOW broadens the soft radius; 1 = authored.
    float cd = length(vec2(cx * 0.85, cy * 5.2)) / GW_GLOW;
    float cloudMass = exp(-cd * cd * 1.3) * 0.20;
    // A faint full-width veil along the same line so the far edge never goes
    // hard — the cloud-feet bleed thinly across the whole horizon.
    float cloudVeil = exp(-cy * cy * 520.0 / (GW_GLOW * GW_GLOW)) * 0.045;
    // Gate the (cheap) fbm break-up to the lit region only — the veil texture
    // is invisible where cloudMass+cloudVeil already vanish.
    float cloudLit = cloudMass + cloudVeil;
    if (cloudLit > 0.001) {
        // Slow noise drift breaks the glow into soft cloud lumps; sideways
        // drift only (x advances with time, y static) so clouds never rise.
        float cloudN = qfbm(vec2(uv.x * 3.0 - cloudDriftT * 0.06, cloudCY * 6.0));
        cloudLit *= (0.60 + 0.7 * cloudN) * GW_DENSITY;
        effect += cloudCol * cloudLit;
    }

    // ---- 綠楊/白沙堤: a faint shore hint on the far water line --------------
    // Cheap and confined: a thin pale white-sand bank exactly on the water
    // line, with a breath of willow-green just above it. A single narrow
    // horizontal strip, dim, biased to the right with the cloud so the left
    // stays open. No noise — just two feathered bands, so it costs nothing.
    float sandY = uv.y - horizon;
    float sandStrip = exp(-sandY * sandY * 2600.0);    // very thin, on the line
    // Lean the bank's brightness toward the right half so it tucks under the
    // cloud focal mass and fades out across the left text rows.
    float shoreBias = smoothstep(0.18, 0.62, uv.x);
    float sand = sandStrip * shoreBias * 0.05 * GW_DENSITY;
    float willowY = uv.y - (horizon + 0.018);          // a touch above the sand
    float willow = exp(-willowY * willowY * 2200.0) * shoreBias * 0.03 * GW_DENSITY;
    effect += sandCol * sand + willowCol * willow;

    // ---- 亂花漸欲迷人眼: drifting spring blossom-motes (residual motion) ----
    // A small fixed set of soft luminous petal-flakes easing DOWN across the
    // field, each on its own slow descent + gentle sway. Density is deliberately
    // tiny so the motes occupy well under 10% of the frame and the center 留白
    // stays open. P.y grows upward, so falling = decreasing y over the loop.
    //
    // FLOAT-SAFETY: fall progress is fract(iTime * rate + phase) — a slow
    // seamless loop; sway feeds mod(iTime, P) into trig so a huge iTime never
    // blows up the oscillation.
    //
    // PERFORMANCE: each mote's coverage is non-zero only within a tight disc
    // around its center (qmote vanishes for length(q) > scale). We compute the
    // center/sway/fade with cheap scalar math, then skip the qmote shape calls
    // for any pixel outside that disc or with fade == 0 — the shape runs for a
    // handful of pixels per mote instead of the whole frame.
    const int MOTES = 9;
    for (int i = 0; i < MOTES; i++) {
        float fi = float(i);
        float h  = qhash1(fi * 1.7 + 0.5);     // primary per-mote random
        float h2 = qhash1(fi * 3.1 + 2.3);     // secondary random
        float h3 = qhash1(fi * 5.9 + 7.1);     // tertiary random

        // Fall: slow, residual — each mote takes ~22-40s to ease down the frame.
        float period = mix(22.0, 40.0, h);
        float rate   = 1.0 / period;
        float t = fract(iTime * rate + h);     // 0 at top, ->1 at bottom

        // Fade: in over the first 12% of the descent, out over the last 18%, so
        // motes appear/vanish softly instead of popping at the frame edge.
        float fade = smoothstep(0.0, 0.12, t) * smoothstep(1.0, 0.82, t);
        if (fade <= 0.0) continue;             // skip fully-faded motes early

        // Vertical drift: start just above the top (1.06), exit just below the
        // far water line so motes settle toward the lake rather than the floor.
        float y = mix(1.06, horizon - 0.02, t);

        // Base column, spread across the width but biased AWAY from dead center
        // so the busiest text rows stay clear (留白). A slight right lean keeps
        // the motes loosely with the cloud focal mass.
        float baseX = 0.14 + 0.74 * h2;

        // Sway: a gentle horizontal oscillation that grows a little as the mote
        // descends (air settling). Two wrapped sines at different rates give an
        // irregular, un-mechanical drift.
        //
        // GW_ENERGY scales AGITATION (sway AMPLITUDE + a shared lateral gust),
        // NOT the fall rate — so dialing it reads as still<->lively air rather
        // than teleporting motes. Default (1.0) keeps the authored sway, no gust.
        float eAmp = 0.45 + 0.55 * GW_ENERGY;                  // 1.0 at default
        float swA = (0.030 + 0.035 * h3) * eAmp;
        float sw1 = sin(mod(iTime, 31.0) * (0.45 + 0.5 * h) + h * 6.2831853);
        float sw2 = sin(mod(iTime, 19.0) * (0.9 + 0.6 * h2) + h2 * 6.2831853);
        float sway = (sw1 * 0.7 + sw2 * 0.3) * swA * (0.5 + 0.7 * t);
        // Extra gust that grows ONLY above default — a shared breath of spring
        // air that nudges every mote together when energy is high.
        float gust = sin(mod(iTime, 23.0) * 0.6 + y * 4.0) * 0.035 * max(GW_ENERGY - 1.0, 0.0);
        float x = baseX + sway + gust;

        // Size: most motes tiny, a couple slightly larger for depth. GW_GLOW
        // grows the soft footprint (and the bounding disc below with it).
        float scale = mix(0.012, 0.024, h3) * GW_GLOW;

        // Position relative to mote center, aspect-corrected so it stays round.
        vec2 q = (uv - vec2(x, y)) * vec2(aspect, 1.0);

        // Cheap bounding-disc reject: qmote is zero once length(q) > scale, so
        // skip the shape call (squared distance, tiny margin for the feather).
        float bound = scale * 1.3;
        if (dot(q, q) > bound * bound) continue;

        float mask = qmote(q, scale) * fade;
        // Pale spring blossom with a faint per-mote warmth wobble; brightness
        // modest so motes read as luminous-soft flecks, not blown-out points.
        vec3 col = mix(petalCol, vec3(1.00, 0.92, 0.84), h2 * 0.4);
        // GW_DENSITY scales each mote's coverage so the drift fills lusher (>1)
        // or thins toward 留白 (<1) without changing the COUNT; 1.0 = authored.
        effect += col * mask * 0.34 * GW_DENSITY;
    }

    // Faint cool ambient lift very low on screen only (the water's body),
    // tapering to pure dark above — preserves negative space for text. Low on
    // screen = small uv.y, so ramp up as uv.y -> 0. GW_DENSITY scales it with
    // the rest of the lake's fill so 留白 opens/closes coherently.
    float lowLift = smoothstep(0.22, 0.0, uv.y) * 0.022 * GW_DENSITY;
    effect += vec3(0.20, 0.32, 0.45) * lowLift;

    // Guard every channel >= 0.
    effect = max(effect, vec3(0.0));

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (water, cloud, and
    // blossom-motes alike) so the feeling reads at a glance — cold/bleak (-1)
    // through the authored spring light (0) to warm/tender (+1). Default 0 =
    // identity.
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;

    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
