// 天淨沙·秋思 (Tiānjìngshā · Qiūsī) — Autumn Thoughts — 馬致遠 (Ma Zhiyuan), Yuan
//   古道西風瘦馬。夕陽西下，斷腸人在天涯。
//   "On the old road, west wind, a gaunt horse; the evening sun sinks in the
//    west — the heartbroken traveler at the edge of the world."
//
// A vast desolate dusk plain, almost all 留白. From back to front the scene
// composites:
//   - 夕陽西下 : a large dim blood-orange sun RIGHT of center, SINKING slowly
//     toward a flat horizon over a long loop (it moves DOWNWARD as iTime grows,
//     reddening and dimming as it nears the earth, throwing a low ember band
//     along the horizon line),
//   - a cold grey-violet ground glow hugging only the horizon (the plain reads
//     as emptiness, not a painted floor — the screen center/upper stays dark),
//   - 古道西風 : thin fast horizontal wind-streaks of dust blowing LEFT across
//     the empty old road (the west wind pushes them over the plain at low alpha),
//   - 古道 : a faint pale road-track receding to the right toward the sun,
//   - bare crow-perched branches at the LEFT margin (枯藤老樹昏鴉), still and dark.
// Light is concentrated in the sinking sun + its horizon ember; everything else
// is a dim accent. The left two-thirds and center stay open for terminal text.
//
// Palette: ember-orange sun #ff8c42, dusty rose #f6c5be, near-black branch +
//          crow #06070c, cold grey-violet plain #4a4660.
//
// Four "feeling" dials tune the mood without redrawing the scene: GW_MOOD warms
// or cools the whole frame, GW_ENERGY drives the 西風 dust-flutter, GW_DENSITY
// fills or empties the plain (dust + ground glow), and GW_GLOW blooms the
// sinking sun, its halo and the horizon ember band. All default to the neutral
// baseline so the authored look is reproduced exactly.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls. In this dusk-plain scene they drive:
//   MOOD    — global warm/cool tone over sun, ember, plain and branch alike.
//   ENERGY  — agitation of the 西風 dust-streaks crossing the plain.
//   DENSITY — coverage of the wind-streaks + the cold ground glow (留白).
//   GLOW    — bloom of the sinking sun, its halo and the horizon ember band.
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

float tjHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float tjNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = tjHash(i);
    float b = tjHash(i + vec2(1.0, 0.0));
    float c = tjHash(i + vec2(0.0, 1.0));
    float d = tjHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float tjFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * tjNoise(p); p *= 2.05; a *= 0.5; }
    return v;
}

// Soft round glow in aspect-corrected space. Returns 0..1.
float tjGlow(vec2 p, vec2 c, float r) {
    float d = length(p - c);
    return exp(-d * d / max(r * r, 1e-4));
}

// Signed-ish "is point inside an aspect-space disc" with soft edge.
float tjDisc(vec2 p, vec2 c, float r) {
    return smoothstep(r, r * 0.92, length(p - c));
}

// 1D capsule/segment distance in aspect space (for the branch + twigs).
float tjSeg(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
    return length(pa - ba * h);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                 // host is top-origin: uv.y = 1 at top

    // Sample the terminal glyph layer with the UNFLIPPED coord.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // Aspect-correct so circular glows stay round on any window shape.
    float aspect = iResolution.x / iResolution.y;
    vec2 ap = vec2(uv.x * aspect, uv.y);   // aspected position

    // Seamless looping clocks. Never feed raw iTime to fast oscillators.
    // (The sun's slow descent wraps inline at its use site below.)
    float tWind = mod(iTime, 30.0);    // fast: wind-streak scroll

    vec3 effect = vec3(0.0);

    // The flat horizon where plain meets sky. Everything below is "ground".
    float horizon = 0.40;

    // ---- 夕陽西下 : a large dim blood-orange sun SINKING on the right ----
    // The disc eases DOWNWARD over the long loop, from well above the horizon
    // until it is half-swallowed by it, then loops back. Lower position →
    // redder + dimmer (atmospheric extinction near the earth).
    float sunX = 0.66;                 // RIGHT of center: keeps the left two-
                                       // thirds open for dense terminal text.
    // cos() gives a smooth sink-and-return; phase chosen so it spends most of
    // the loop low and brooding. Range ~horizon+0.18 (high) .. horizon-0.02
    // (half set), so it genuinely touches/dips the horizon line.
    float sunPhase = mod(iTime, 540.0) * (6.2831853 / 540.0);
    float sunY = horizon + 0.085 + 0.105 * cos(sunPhase);
    vec2  sunC = vec2(sunX * aspect, sunY);
    float sunR = 0.16;                 // a HUGE low sun, the scene's focal point

    // How low is it? 1 when sitting on the horizon, 0 when high.
    float lowness = smoothstep(horizon + 0.19, horizon, sunY);

    // Disc: a soft dim body (dusk sun is not a hot lamp). Slight limb glow.
    // GW_GLOW widens the soft bloom radii (body + halo) for a dreamier, hazier
    // dusk — the hard disc geometry (discCore) stays fixed so the disc edge
    // still reads cleanly. Default 1.0 = authored radii.
    float discCore = tjDisc(ap, sunC, sunR);
    float discBody = tjGlow(ap, sunC, sunR * 0.95 * GW_GLOW);
    // Halo: broad, low — a smoggy dusk corona, not a bright flare.
    float sunHalo  = tjGlow(ap, sunC, sunR * 2.4 * GW_GLOW) * 0.40;

    // Color reddens as it lowers: ember-orange high → dusty blood-rose low.
    vec3 sunHi  = vec3(1.00, 0.55, 0.26);  // ember-orange #ff8c42
    vec3 sunLo  = vec3(0.96, 0.41, 0.30);  // deepened blood-rose at the earth
    vec3 sunCol = mix(sunHi, sunLo, lowness);
    // Overall dim & dimming-as-it-sets so it stays "dying sun", never blowout.
    float sunDim = mix(0.78, 0.50, lowness);

    // A faint dusty striation crossing the disc (haze layered over the sun).
    float sunHaze = 0.85 + 0.15 * tjFbm(vec2(uv.x * 8.0 - tWind * 0.4, uv.y * 30.0));

    effect += sunCol * (discCore * 0.70 + discBody * 0.45) * sunDim * sunHaze;
    effect += mix(sunHi, sunLo, 0.6) * sunHalo * sunDim;

    // ---- horizon ember band : the sun's light pooled along the far earth ----
    // A narrow warm band ONLY at the horizon, brightest under the sun and
    // fading left across the plain. This anchors the ground without washing
    // the frame — above and well-below the horizon stay dark.
    {
        float band = smoothstep(0.060 * GW_GLOW, 0.0, abs(uv.y - horizon));
        // Brightest beneath the sun, trailing off toward the left margin.
        float spread = smoothstep(0.0, 1.05, 1.0 - abs(uv.x - sunX) * 1.15);
        float emberFlicker = 0.92 + 0.08 * sin(mod(iTime, 19.0) * 0.7 + uv.x * 6.0);
        vec3 emberCol = mix(vec3(0.55, 0.22, 0.18), sunLo, spread);
        effect += emberCol * band * spread * emberFlicker * 0.34 * mix(0.7, 1.0, lowness);
    }

    // ---- cold grey-violet plain : a whisper of ground glow under horizon ----
    // Only the strip just below the horizon catches a cold cast; it fades to
    // black toward the bottom so the lower screen stays open. Cold violet
    // against the warm sun = the desolate autumn-dusk contrast.
    {
        float depth = horizon - uv.y;                       // >0 below horizon
        float ground = smoothstep(0.0, 0.30, depth) * smoothstep(0.55, 0.10, depth);
        // Very faint fbm texture so the plain isn't a flat smear.
        float grain = 0.6 + 0.4 * tjFbm(vec2(uv.x * 4.0 + 3.0, uv.y * 5.0));
        // GW_DENSITY lifts the ground coverage so the plain fills more (lush)
        // or recedes toward pure 留白 (sparse). Default 1.0 = authored alpha.
        vec3 plainCol = vec3(0.29, 0.27, 0.37);             // grey-violet #4a4660
        effect += plainCol * ground * grain * 0.075 * GW_DENSITY;
    }

    // ---- 西風 : thin fast horizontal wind-streaks (dust) blowing LEFT ----
    // Low-alpha streaks scrolling leftward (west wind moving across the plain).
    // Concentrated in a band straddling the horizon where dust would catch the
    // light; warm where lit by the sun, cool out on the plain.
    {
        float windScroll = fract(tWind * (1.0 / 30.0)) * 4.0;
        // GW_ENERGY scales wind AGITATION (a vertical flutter amplitude on the
        // streaks), NOT the scroll rate — so the dial reads as calm<->gusty
        // wind rather than teleporting the dust field. The flutter is gated by
        // max(GW_ENERGY-1,0) so it is exactly zero at default (1.0).
        float gust = sin(mod(iTime, 23.0) * 0.9 + uv.x * 7.0) * 0.6 * max(GW_ENERGY - 1.0, 0.0);
        // Sharp thin horizontal layers via fract on a y-coordinate; each layer
        // scrolls in x. The streaks live around the horizon ±.
        float yBand = smoothstep(0.22, 0.0, abs(uv.y - (horizon + 0.02)));
        float streakField = tjFbm(vec2(uv.x * 5.0 + windScroll, uv.y * 26.0 + gust));
        float streaks = smoothstep(0.55, 0.95, streakField);
        // Warm near the sun, cooling toward the left.
        float warmth = smoothstep(0.0, 1.0, 1.0 - abs(uv.x - sunX));
        vec3 dustCol = mix(vec3(0.50, 0.46, 0.52), vec3(0.96, 0.62, 0.42), warmth);
        // GW_DENSITY scales how much dust fills the plain (coverage alpha).
        // Default 1.0 = authored.
        effect += dustCol * streaks * yBand * 0.085 * GW_DENSITY;
    }

    // ---- 古道 : a faint pale road-track receding to the right ----
    // A thin lightening of the plain just under the horizon, narrowing toward
    // the sun (the old road running empty into the dusk). Kept very dim.
    {
        // Road runs along the horizon, brighter toward the right (vanishing
        // toward the sun), within a shallow strip below it.
        float roadDepth = horizon - uv.y;
        float onStrip = smoothstep(0.0, 0.02, roadDepth) * smoothstep(0.12, 0.03, roadDepth);
        float toRight = smoothstep(0.25, 0.85, uv.x);
        effect += vec3(0.45, 0.40, 0.42) * onStrip * toRight * 0.05;
    }

    // ---- 枯藤老樹昏鴉 : a bare old limb with a perched crow, upper-LEFT ----
    // A withered branch reaches in from the top-left corner and droops to the
    // right; fine bare twigs hang DOWN from it (the gnarled autumn tree), with a
    // single dusk crow perched near the tip. All dark — it occludes the light
    // behind it, and hugs the margin so the center stays clear. Near-still: only
    // the crow gives a barely-there shuffle.
    {
        // Anchor points of the main limb (aspect space), entering from the
        // corner and sagging down-right.
        vec2 a0 = vec2(0.0,         1.04);
        vec2 a1 = vec2(0.13 * aspect, 0.88);
        vec2 a2 = vec2(0.27 * aspect, 0.80);
        float twig = 0.0;
        // Main limb in two tapering strokes (thicker near the trunk).
        twig = max(twig, smoothstep(0.019, 0.006, tjSeg(ap, a0, a1)));
        twig = max(twig, smoothstep(0.013, 0.004, tjSeg(ap, a1, a2)));
        // A second limb forking upward-right off the elbow.
        twig = max(twig, smoothstep(0.012, 0.004,
                  tjSeg(ap, a1, vec2(0.235 * aspect, 0.98))));
        // Fine bare twigs HANGING DOWN from the limb (枯藤 — withered vines).
        twig = max(twig, smoothstep(0.0075, 0.003,
                  tjSeg(ap, vec2(0.085 * aspect, 0.905), vec2(0.075 * aspect, 0.80))));
        twig = max(twig, smoothstep(0.0070, 0.003,
                  tjSeg(ap, vec2(0.150 * aspect, 0.865), vec2(0.165 * aspect, 0.74))));
        twig = max(twig, smoothstep(0.0065, 0.003,
                  tjSeg(ap, vec2(0.210 * aspect, 0.825), vec2(0.198 * aspect, 0.72))));
        twig = max(twig, smoothstep(0.0060, 0.003,
                  tjSeg(ap, vec2(0.235 * aspect, 0.812), vec2(0.255 * aspect, 0.70))));
        twig = clamp(twig, 0.0, 1.0);

        // A perched crow near the limb tip: a small dark teardrop body with a
        // tail nub, with a barely-there shuffle so it reads as alive but still.
        float crowShift = 0.004 * sin(mod(iTime, 37.0) * 0.4);
        vec2 crowC = vec2(0.275 * aspect, 0.815 + crowShift);
        float crowBody = smoothstep(0.020, 0.010,
                         length((ap - crowC) * vec2(1.05, 1.35)));
        float crowTail = smoothstep(0.012, 0.005,
                         tjSeg(ap, crowC, crowC + vec2(0.030 * aspect, 0.008)));
        twig = max(twig, max(crowBody, crowTail));

        vec3 branchCol = vec3(0.022, 0.024, 0.040);
        effect = effect * (1.0 - twig) + branchCol * twig;
    }

    // ---- MANDATORY composite : additive, luminous-on-dark, text legible ----
    effect = max(effect, vec3(0.0));

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (sun, ember band,
    // cold plain, dust and the dark branch alike) so the feeling reads at a
    // glance — bleak/cold (-1) through the authored dusk (0) to warm/tender
    // (+1). Default 0 = identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;
    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}