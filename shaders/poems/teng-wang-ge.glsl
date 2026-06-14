// 滕王閣序 (Téngwáng Gé Xù) — Preface to the Pavilion of Prince Teng — 王勃 (Wáng Bó), Tang
//   落霞與孤鶩齊飛，秋水共長天一色。
//   "The falling rose-glow and a lone wild duck fly together;
//    the autumn waters merge with the boundless sky into one single color."
//
// The canonical lone-bird-at-sunset vista. Water and sky share ONE seamless
// rose-gold wash (共長天一色) — no drawn horizon, only a barely-there shimmer
// band where they meet to whisper "water starts here". The scene composites,
// back to front:
//   - 共長天一色 : a luminous rose-gold glow that pools toward the TOP (the
//     burning sky) and toward the BOTTOM (its reflection on the autumn water),
//     leaving the CENTER — where terminal text sits — open and near-dark
//     (留白). The upper glow and its lower reflection are the same graded
//     field, meeting at a soft merge-zone (uv.y ~ 0.42) that never resolves
//     into a hard seam — a faint travelling shimmer there is the ONLY cue that
//     the lower half is water, felt rather than drawn.
//   - 落霞 : 2-3 long soft rose-gold cloud-streaks high in the sky, drifting
//     slowly SIDEWAYS together and breathing gently.
//   - 孤鶩 : ONE lone wild-duck silhouette gliding across at the same altitude
//     as the cloud (齊飛), on a shallow arc with a slow sine wing-beat. Rim-lit
//     by the low sun so it reads dark body / luminous gold edge. It crosses
//     left to right, dissolves into the glow at the far margin, and respawns at
//     the near margin — exactly one bird at any instant.
//   - 秋水 : a faint warm specular shimmer drifting low on the water wash so the
//     merge-zone shivers, reinforcing 一色.
// Light pools top + bottom; the center stays open so glyphs read cleanly.
//
// Palette: rose-gold #ffad47 / blush #f6c5be high, a thin pale gold-cyan
//          #c9daf8 accent at the merge zone, lone duck #fef1d1 rim over a near
//          -black body, dim warm water undertone #7a4706.
//
// Four "feeling" dials tune the scene (all-default = authored look): GW_MOOD
// warms/cools the whole sunset wash, GW_ENERGY drives motion agitation (cloud
// breath, the duck's arc/bob, seam + water shimmer), GW_DENSITY fills vs 留白
// (wash, cloud-streaks, shimmer coverage), and GW_GLOW softens the glows, cloud
// feathers, shimmer edges and the duck's luminous rim.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls.
//   GW_MOOD    : global warm/cool tint over the whole sunset wash, clouds,
//                duck rim and water shimmer (-1 cold/blue .. 0 .. +1 warm).
//   GW_ENERGY  : motion AGITATION — cloud sideways drift, the lone duck's
//                wing-beat/body-bob arc, the seam ripple and water shimmer
//                breathe harder above 1 and settle toward stillness below.
//   GW_DENSITY : fill vs 留白 — the rose-gold wash, cloud-streak coverage and
//                water shimmer thicken (>1 lusher) or thin out (<1 sparser).
//   GW_GLOW    : bloom/softness of every glow, cloud feather, shimmer edge and
//                the duck's luminous rim (>1 dreamier, <1 crisper).
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

float twHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float twNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = twHash(i);
    float b = twHash(i + vec2(1.0, 0.0));
    float c = twHash(i + vec2(0.0, 1.0));
    float d = twHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float twFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * twNoise(p); p *= 2.05; a *= 0.5; }
    return v;
}

// Lone-duck silhouette in duck-local space (centered, x roughly in [-2,2]).
// `beat` ∈ [-1,1] drives the wing sweep. Returns a soft 0..1 mask of the whole
// bird. The classic distant-waterfowl read is a shallow "⌒⌒": a small plump
// body with two SWEPT, CURVED wings — each rises from the shoulder, arcs up to
// a rounded peak mid-span, then droops to a tapered tip. Curved (not straight
// V's, which read as antennae) and broad at the root so it reads as wings.
float twDuck(vec2 q, float beat) {
    // Body: a small plump ellipse, sitting in the dip between the two wings.
    vec2 b = q / vec2(0.58, 0.34);
    float body = 1.0 - smoothstep(0.80, 1.10, length(b));
    // Head/neck: a small blob leading the body (+x = flight direction).
    vec2 h = (q - vec2(0.64, 0.09)) / vec2(0.30, 0.26);
    float head = 1.0 - smoothstep(0.72, 1.08, length(h));
    // Wings: one swept hump per side. `along` runs 0 at the shoulder to 1 at the
    // tip; the arc rises as sin(pi*along) and the tip droops slightly past the
    // peak. `beat` lifts the whole arc (up-stroke) and flattens it (glide).
    float span  = 1.55;                                   // wing reach each side
    float aq    = abs(q.x);
    float along = clamp(aq / span, 0.0, 1.0);
    float lift  = 0.50 + 0.34 * beat;                     // glide..up-stroke
    float arcY  = lift * sin(3.14159265 * along) - 0.12 * along * along;  // hump + tip droop
    float thick = mix(0.20, 0.02, along);                 // broad root -> point tip
    float onWing = step(0.02, aq) * (1.0 - step(span, aq));
    float wing = onWing * (1.0 - smoothstep(thick, thick + 0.06, abs(q.y - arcY)));
    return clamp(body + head + wing, 0.0, 1.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                 // host is top-origin: uv.y = 1 at top

    // Sample the terminal glyph layer with the UNFLIPPED coord.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // Aspect-correct so circular glows / the duck stay shaped on any window.
    float aspect = iResolution.x / iResolution.y;
    vec2 ap = vec2(uv.x * aspect, uv.y);   // aspected position

    // Seamless looping clocks. Never feed raw iTime to fast oscillators.
    float tDrift = mod(iTime, 240.0);  // slow horizontal cloud drift
    float tCross = mod(iTime, 48.0);   // the duck's traverse across the sky
    float tWave  = mod(iTime, 24.0);   // water shimmer
    float tBeat  = mod(iTime, 3.2);    // wing-beat + body bob

    // GW_ENERGY scales motion AGITATION (amplitudes), never the oscillator
    // RATES — dialing it must read as calm<->lively, not teleporting elements.
    // eAmp = 1.0 at the default so the authored motion is untouched.
    float eAmp = 0.45 + 0.55 * GW_ENERGY;

    vec3 effect = vec3(0.0);

    // Sunset palette.
    vec3 roseGold = vec3(1.00, 0.66, 0.26);    // #ffad47 rose-gold
    vec3 blush    = vec3(1.00, 0.80, 0.66);    // warm blush (lifted from #f6c5be)
    vec3 mergeCol = vec3(0.84, 0.83, 0.86);    // thin pale gold-cyan accent
    vec3 waterCol = vec3(0.56, 0.32, 0.06);    // #7a4706 warm water undertone

    // ---- 共長天一色 : one seamless wash pooling TOP (sky) + BOTTOM (water) ----
    // The single allowed full-frame element, deliberately HOLLOW in the middle:
    // luminance burns toward the top edge (sky) and rises again toward the
    // bottom edge (its water reflection), pressed to near-zero across the
    // central text band (留白). No drawn horizon — the upper glow and lower
    // reflection are one graded rose field meeting at a soft merge-zone. A slow
    // fbm tint keeps it alive rather than a flat ramp.
    {
        // Sky pool: a strong rose-gold glow that intensifies toward the top.
        float sky = smoothstep(0.40, 1.0, uv.y);
        sky = sky * sky;                       // press the glow to the top edge
        // Water pool: a softer reflected glow toward the bottom edge.
        float water = smoothstep(0.34, 0.0, uv.y);
        water = water * water;

        // Slow living tint so the wash breathes instead of being a flat ramp.
        float tint = twFbm(vec2(uv.x * 1.5 + tDrift * 0.012, uv.y * 1.2 + 3.0));
        tint = 0.82 + 0.26 * tint;

        // Sky color: rose-gold near the top melting to warm blush lower, with a
        // whisper of the pale gold-cyan accent right at the merge zone so the
        // seam dissolves (一色). The blue accent is intentionally THIN so the
        // field stays unmistakably golden.
        vec3 skyCol = mix(blush, roseGold, smoothstep(0.45, 1.0, uv.y));
        skyCol = mix(skyCol, mergeCol, smoothstep(0.62, 0.42, uv.y) * 0.30);
        // Water reflection: rose-gold sinking into the dim warm undertone.
        vec3 watCol = mix(waterCol, roseGold * 0.92, smoothstep(0.0, 0.34, uv.y));

        // GW_DENSITY thickens (>1 lusher) or thins (<1 sparser) the pooled
        // wash that fills top + bottom; default 1 leaves the authored balance.
        effect += skyCol * sky   * tint * 0.62 * GW_DENSITY;
        effect += watCol * water * tint * 0.46 * GW_DENSITY;
    }

    // ---- merge-zone : the felt seam where water begins (NOT a drawn horizon) --
    // 共長天一色 forbids a hard line, but a perfectly seamless ramp reads as a
    // flat gradient. So a single faint travelling shimmer hugs uv.y ~ 0.42: just
    // enough rippling light for the eye to know the lower half is reflecting
    // water, never enough to resolve into an edge. This is the scene's only
    // depth cue. Kept dim and pale so it dissolves into the 一色 wash.
    {
        // GW_GLOW softens (>1) or sharpens (<1) the felt seam's feather width.
        float seam = smoothstep(0.085 * GW_GLOW, 0.0, abs(uv.y - 0.42));
        if (seam > 0.0) {
            float scroll = fract(tWave * (1.0 / 24.0)) * 1.6;
            float ripple = twFbm(vec2(uv.x * 4.2 - scroll, uv.y * 9.0 + 5.0));
            ripple = smoothstep(0.46, 0.82, ripple);
            // GW_ENERGY scales the shimmer's breathing AMPLITUDE only.
            float breath = 0.72 + 0.28 * eAmp * sin(tWave * 0.22 + 1.1);
            effect += mergeCol * seam * ripple * breath * 0.075;
        }
    }

    // ---- 落霞 : 2-3 long soft rose-gold cloud-streaks drifting sideways ----
    // Elongated horizontal fbm bands high in the sky. They translate slowly to
    // the RIGHT together over the long loop and breathe gently. Confined to the
    // upper field so the center stays open. The lowest streak sets the altitude
    // the lone duck flies level with (齊飛).
    {
        float drift = fract(tDrift * (1.0 / 240.0));   // 0..1 rightward
        const int NCLOUD = 3;
        for (int i = 0; i < NCLOUD; i++) {
            float fi = float(i);
            float cy = 0.70 + 0.075 * fi;              // 0.70, 0.775, 0.85
            // GW_GLOW softens (>1) / sharpens (<1) each streak's vertical feather.
            float vEnv = smoothstep(0.055 * GW_GLOW, 0.0, abs(uv.y - cy));
            if (vEnv <= 0.0) continue;
            // Long horizontal fbm scrolling with drift; per-streak phase offset.
            float sx = uv.x * 2.1 - drift * 2.0 + fi * 4.13;
            float band = twFbm(vec2(sx, cy * 6.0 + fi * 1.7));
            band = smoothstep(0.44, 0.90, band);
            // GW_ENERGY scales the gentle breathing AMPLITUDE (not the drift rate).
            float breath = 0.76 + 0.24 * eAmp * sin(tWave * 0.20 + fi * 1.9);
            vec3 cloudCol = mix(roseGold, blush, smoothstep(0.76, 0.90, cy));
            // GW_DENSITY makes the cloud-streaks lusher (>1) or sparser (<1).
            effect += cloudCol * vEnv * band * breath * 0.55 * GW_DENSITY;
        }
    }

    // ---- 孤鶩 : ONE lone wild duck gliding across, level with the cloud ----
    // Bird-and-cloud travelling TOGETHER (齊飛) is the whole point, so the duck
    // flies at the lowest streak's altitude and drifts the same direction. It
    // crosses LEFT -> RIGHT on a shallow arc, beats its wings slowly, and is
    // rim-lit by the low sun so it reads dark body with a luminous gold edge.
    // Exactly one at any instant: it fades into the glow near the right margin
    // as it respawns at the left.
    {
        float p = fract(tCross * (1.0 / 48.0));    // 0..1 traverse, L->R
        // March across with a margin beyond both edges so entry/exit are off
        // -screen rather than popping mid-frame.
        float duckX = mix(-0.10, 1.10, p) * aspect;
        // Shallow arc: glides just under the lowest cloud (cy=0.70), dipping a
        // little mid-pass then easing back up — a gentle bezier feel. Sits low
        // enough that the bright sky-glow pools ABOVE and behind it, so the dark
        // body has luminance to bite against (the silhouette must POP).
        // GW_ENERGY scales the lone duck's motion AGITATION — a deeper arc dip
        // and a livelier body-bob above 1, calmer/flatter below. Both amplitudes
        // vanish at the path endpoints, so scaling never makes the bird jump.
        float arc = 0.665 - 0.045 * eAmp * sin(p * 3.14159265);
        float beat = sin(tBeat * (6.2831853 / 3.2));   // -1..1 wing-beat
        float bob  = 0.007 * eAmp * beat;              // body rises on up-stroke
        vec2 duckC = vec2(duckX, arc + bob);

        // Edge fade so the lone duck dissolves into the rose field at both
        // margins (落霞 與 孤鶩 齊飛 — bird melting into the same glow).
        float edgeFade = smoothstep(0.0, 0.10, p) * smoothstep(1.0, 0.90, p);

        // Duck-local coords. Small on screen — a distant solitary bird.
        float duckScale = 0.060;
        vec2 q = (ap - duckC) / duckScale;
        if (abs(q.x) < 3.0 && abs(q.y) < 2.0) {
            float duckMask = twDuck(q, beat) * edgeFade;
            if (duckMask > 0.0) {
                // Rim light: the silhouette edge catches the sun-glow. Interior
                // is near-black; the feathered edge flares gold. Split the mask
                // into a solid core (dark body) and its soft shell (luminous
                // rim) so the bird reads dark-to-gold against the sky.
                // Widen the solid core so more of the bird reads as dark body,
                // leaving a thin luminous pinion edge — the silhouette must bite
                // hard against the bright sky.
                // GW_GLOW feathers the dark-body / luminous-rim split: a softer,
                // dreamier gold edge above 1, a crisper silhouette below. The
                // band widens symmetrically about its center so GW_GLOW=1 is the
                // exact authored 0.38..0.74 transition.
                float coreLo = 0.56 - 0.18 * GW_GLOW;
                float coreHi = 0.56 + 0.18 * GW_GLOW;
                float core = smoothstep(coreLo, coreHi, duckMask);  // dark interior
                float rim  = duckMask * (1.0 - core);               // luminous shell
                vec3 duckDark = vec3(0.023, 0.027, 0.047);      // #06070c body
                vec3 duckRim  = vec3(0.996, 0.945, 0.820);      // #fef1d1 gold edge

                // Dark body OCCLUDES the wash behind it (near-total), then the
                // rim ADDS glow. Stronger occlusion = a blacker, sharper bird.
                effect *= (1.0 - core * 0.94);
                effect += duckDark * core * 0.10;
                effect += duckRim  * rim  * 1.00;
            }
        }
    }

    // ---- 秋水 : faint warm specular shimmer drifting low on the water wash ----
    // A whisper of soft travelling glints in the low water pool so the seam
    // between water and air never resolves — it shivers (一色). Dim and low so
    // the center stays open. Built from a smooth scrolling fbm (no hard stripes).
    {
        // GW_GLOW softens (>1) / sharpens (<1) the low water band's soft edge.
        float band = smoothstep(0.18 * GW_GLOW, 0.0, abs(uv.y - 0.16));
        if (band > 0.0) {
            float scroll = fract(tWave * (1.0 / 24.0)) * 2.0;
            float g = twFbm(vec2(uv.x * 6.0 - scroll, uv.y * 5.0 + 11.0));
            float shimmer = smoothstep(0.48, 0.84, g);
            // GW_ENERGY scales the shimmer's breathing AMPLITUDE only.
            float breath = 0.7 + 0.3 * eAmp * sin(tWave * 0.26);
            // GW_DENSITY thickens (>1) / thins (<1) the specular glint coverage.
            effect += roseGold * band * shimmer * breath * 0.26 * GW_DENSITY;
        }
    }

    // ---- soft low vignette : depth, removes light only ----
    // Gently sinks the very bottom corners so the water pool reads as a deep,
    // settled surface rather than an even floor of light. Multiplicative and
    // keyed to the bottom edge, so it never adds light and never touches the
    // central text band.
    {
        float low = smoothstep(0.30, 0.0, uv.y);          // 0 above, 1 at floor
        float side = smoothstep(0.30, 0.95, abs(uv.x - 0.5) * 2.0);
        effect *= 1.0 - low * side * 0.30;
    }

    // ---- MANDATORY composite : additive, luminous-on-dark, text legible ----
    effect = max(effect, vec3(0.0));

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (sky wash, clouds,
    // the lone duck's rim and the water shimmer alike) so the feeling reads at a
    // glance — cool/autumnal (-1) through the authored rose-gold (0) to a warmer,
    // more golden burn (+1). Default 0 = identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;
    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}