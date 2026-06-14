// 獨坐敬亭山 (Dú Zuò Jìngtíng Shān) — Sitting Alone by Jingting Mountain
//   李白 (Lǐ Bái), Tang
//   眾鳥高飛盡，孤雲獨去閒。
//   "The flocks of birds have flown high and vanished;
//    a lone cloud drifts away, idle and free."
//
// A wide, emptying dusk sky over a single quiet mountain. The scene is a slow
// TWO-PHASE "emptying to nothing", composited from back to front:
//   - a low, near-black flat MOUNTAIN MASS hugging the bottom edge (the still
//     Jingting Shan the watcher faces); a faint dusk rim-glow sits just above
//     its ridge so it reads as a silhouette against the fading light,
//   - a pale graded DUSK GLOW kept to the TOP band and edges only — a vignette,
//     never a full-frame wash; the CENTER (where terminal text sits) stays
//     ~iBackgroundColor (留白),
//   - Phase 1 高飛盡: a FLOCK of ~12 tiny luminous bird-marks streaming UPWARD
//     and to the RIGHT, scaling and fading to nothing as they climb (toward the
//     top of the frame as iTime grows),
//   - Phase 2 孤雲獨去: after the birds are gone, ONE soft lone cloud drifts
//     slowly LEFT-TO-RIGHT high in the sky and fades out, leaving the heavens
//     bare,
//   - then a long held STILLNESS — the 留白 that remains after everything
//     departs — before the very slow loop begins again.
//
// Palette: muted dusk slate-violet #4a4660 → pale ash, near-black mountain
//          mass #06070c, birds + cloud in soft luminous off-white #f4f8ff.
//
// Direction note: glsl_image / Ghostty render UPRIGHT (uv.y = 1 at TOP). Birds
// RISE, so they move toward the top as iTime increases — verified by frame
// renders. The cloud drifts laterally left→right.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls. Here they drive: MOOD = global dusk
// warm/cool tone; ENERGY = wing-bob + cloud-bob agitation (amplitude, not rate);
// DENSITY = how full the sky reads (dusk wash + flock + cloud coverage vs 留白);
// GLOW = softness of the bird strokes, cloud body, dusk rim and bloom.
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

float jtHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float jtNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = jtHash(i);
    float b = jtHash(i + vec2(1.0, 0.0));
    float c = jtHash(i + vec2(0.0, 1.0));
    float d = jtHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float jtFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * jtNoise(p); p *= 2.07; a *= 0.5; }
    return v;
}

// A single tiny bird "mark": two short strokes meeting at an apex, like the
// classic distant-bird brushstroke (a soft shallow "v"). p is aspect-corrected
// position relative to the bird center; s is on-screen scale. Returns 0..1.
float jtBird(vec2 p, float s) {
    // Normalise to the bird's local frame.
    p /= max(s, 1e-4);
    // Slight wing droop: each wing is a line segment from the apex (0,0)
    // sloping down-outwards. Distance to the nearer wing stroke.
    float x = abs(p.x);
    // Wing line: y = -k*x for x in [0, wingLen]. Distance to that ray.
    float k = 0.55;                       // wing droop slope
    float wingLen = 1.0;
    float xc = clamp(x, 0.0, wingLen);
    vec2 onWing = vec2(xc, -k * xc);
    float d = length(vec2(x, p.y) - onWing);
    // Thin soft stroke.
    return exp(-d * d / 0.10);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                 // host is top-origin: uv.y = 1 at top

    // Sample the terminal glyph layer with the UNFLIPPED coord.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // Aspect-correct so circular glows / birds stay round on any window shape.
    float aspect = iResolution.x / iResolution.y;
    vec2 ap = vec2(uv.x * aspect, uv.y);

    vec3 effect = vec3(0.0);

    // GW_ENERGY scales motion AGITATION (the wing-bob / cloud-bob AMPLITUDES),
    // never the oscillator rates — so dialing it reads as calm<->lively air
    // instead of teleporting the flock/cloud. Default (1.0) keeps the authored
    // amplitudes exactly. eAmp = 1.0 at GW_ENERGY=1.
    float eAmp = 0.45 + 0.55 * GW_ENERGY;

    // ===================== timeline / seamless loop =======================
    // One full cycle = CYCLE seconds. We build a normalised phase in [0,1)
    // with mod(), so iTime never reaches the fast oscillators raw.
    //   ph 0.00 .. 0.34  : Phase 1, birds rise and vanish (高飛盡)
    //   ph 0.30 .. 0.66  : Phase 2, lone cloud drifts out (孤雲獨去)
    //   ph 0.66 .. 1.00  : held stillness, empty sky (留白)
    const float CYCLE = 48.0;
    float ph = fract(iTime / CYCLE);        // 0..1, monotone & loop-safe

    // ===================== dusk glow — TOP/edge vignette only ==============
    // A pale dusk wash that lives in the TOP band and the side margins, and
    // decays to ~0 across the middle and bottom-center. This evokes a vast
    // pale sky WITHOUT washing the frame: the center stays ~iBackgroundColor
    // so glyphs read (留白). The dusk also gently dims over the cycle as the
    // sky "empties" toward stillness.
    {
        // Top-weighted falloff: brightest at the very top edge, gone by mid.
        float topBand = smoothstep(0.18, 1.0, uv.y);
        topBand *= topBand;                              // steeper → clears center
        // Faint side margins so the corners feel like open sky, center dark.
        float sideX = smoothstep(0.34, 0.0, uv.x) + smoothstep(0.66, 1.0, uv.x);
        sideX = clamp(sideX, 0.0, 1.0) * 0.5;
        float skyMask = clamp(topBand + topBand * sideX, 0.0, 1.0);
        // GATE: the dusk only contributes where skyMask is non-negligible.
        // Below uv.y≈0.18 topBand is 0, so skyMask is 0 across the whole lower
        // band and center floor — skip the fbm there entirely (lossless).
        if (skyMask > 0.0015) {
            // Very soft fbm so the dusk isn't a flat gradient — wisps of light.
            float wisp = 0.65 + 0.35 * jtFbm(vec2(uv.x * 2.2 + 3.0, uv.y * 2.6));
            // The sky cools/empties as the cycle progresses, then refills slowly.
            float dim = 0.80 + 0.20 * cos(ph * 6.2831853); // brightest at loop start
            // Dusk slate-violet high, paler warm ash lower in the band — a fading
            // evening sky. Kept top-weighted so the glow never reaches the center.
            vec3 duskHi = vec3(0.34, 0.31, 0.44);          // slate-violet #4a4660
            vec3 duskLo = vec3(0.40, 0.37, 0.39);          // pale warm ash
            vec3 duskCol = mix(duskLo, duskHi, smoothstep(0.3, 1.0, uv.y));
            // GW_DENSITY scales how much the dusk fills the sky (lusher >1, more
            // 留白 <1); default 1.0 leaves the authored wash. GW_GLOW already
            // softens the rim below — the wash itself is a smooth gradient.
            effect += duskCol * skyMask * wisp * dim * 0.42 * GW_DENSITY;
        }
    }

    // ===================== mountain mass — bottom silhouette ==============
    // A low, near-black ridge hugging the bottom. Two broad humps from a
    // smooth combination of cosines + a little fbm roughening, so it reads as
    // one quiet mountain rather than a straight line. A thin dusk rim-glow
    // sits just ABOVE the ridge so the silhouette separates from the sky.
    //
    // GATE: the ridge sits at uv.y in [0.07,0.30]; both the silhouette fill and
    // the rim-glow vanish above uv.y≈0.36 (rim ~ exp(-0.06*130)=e^-7.8≈0).
    // For the whole sky above that we skip the ridge fbm + rim math entirely.
    if (uv.y < 0.36) {
        // Ridge height as a function of x (in uv space, 0..1 across screen).
        float x = uv.x;
        float ridge = 0.150
                    + 0.075 * cos((x - 0.42) * 3.0)      // main broad peak
                    + 0.030 * cos((x + 0.10) * 6.5)      // secondary shoulder
                    + 0.022 * (jtFbm(vec2(x * 5.0, 9.0)) - 0.5) * 2.0; // roughen
        ridge = clamp(ridge, 0.07, 0.30);

        // Solid mountain below the ridge line (near-black, lifts bg slightly
        // so it's a touch darker/cooler than open sky — a true silhouette).
        float inMtn = smoothstep(0.004, -0.004, uv.y - ridge);
        vec3 mtnCol = vec3(0.018, 0.020, 0.030);         // near-black #06070c-ish
        effect += mtnCol * inMtn;

        // Thin dusk rim just above the ridge: a hairline of fading light that
        // makes the dark mass read as a mountain against dusk. Above-only.
        float rimDist = uv.y - ridge;                    // >0 above the ridge
        // GW_GLOW widens the rim's soft falloff (dividing the decay constant by
        // GW_GLOW lengthens the bloom); default 1.0 keeps the authored hairline.
        float rim = exp(-max(rimDist, 0.0) * (130.0 / GW_GLOW)) * step(0.0, rimDist);
        // Rim fades as the sky empties (tracks the dusk dim).
        float rimDim = 0.78 + 0.22 * cos(ph * 6.2831853);
        vec3 rimCol = vec3(0.40, 0.36, 0.42);            // warm-cool dusk rim
        effect += rimCol * rim * rimDim * 0.45;
    }

    // ===================== Phase 1 — 眾鳥高飛盡 : the flock rises & vanishes =
    // ~12 tiny bird-marks streaming UPWARD and to the RIGHT, in a loose
    // diagonal skein. Each bird has a staggered launch so they trail one after
    // another; as the flock climbs it scales DOWN and fades to nothing near
    // the top of the sky (高飛盡 — "flown high and gone"). Constant loop bound.
    {
        // After the flock is gone we don't draw it (saves it from reappearing
        // mid-air); gate the whole flock by a window that opens then closes.
        float flockGate = smoothstep(0.02, 0.10, ph) * smoothstep(0.40, 0.26, ph);
        // GATE: for ~74% of the cycle the flock window is shut — skip the whole
        // 12-bird loop. The marks also never sit below uv.y≈0.33 (launch row)
        // or above ~0.9, so pixels well outside that band can't be lit.
        if (flockGate > 0.0 && uv.y > 0.30 && uv.y < 0.92) {
            // Phase-1 progress 0..1 (active only in the first stretch of cycle).
            float p1 = smoothstep(0.0, 0.30, ph);        // 0 at start → 1
            const int NBIRDS = 12;
            for (int i = 0; i < NBIRDS; i++) {
                float fi = float(i);
                // Per-bird launch stagger: later birds start later → a trailing
                // skein rather than a rigid block.
                float stagger = fi / float(NBIRDS) * 0.45;
                float prog = clamp((p1 - stagger) / max(1.0 - stagger, 1e-3), 0.0, 1.0);
                // Opacity: fades in fast at launch, fades to zero as it nears top.
                float fade = smoothstep(0.0, 0.08, prog) * (1.0 - smoothstep(0.55, 1.0, prog));
                // Birds not yet launched or fully faded contribute nothing — skip
                // the jtBird exp() (and the bird is off this pixel anyway).
                if (fade <= 0.0) continue;

                // Launch point: low and spread across the lower-left/mid sky, just
                // above the ridge. Up-and-to-the-right travel.
                float bx0 = 0.18 + 0.045 * fi + 0.05 * jtHash(vec2(fi, 1.0));
                float by0 = 0.34 + 0.02 * jtHash(vec2(fi, 7.0));
                // Diagonal travel: rightward + strongly upward (toward top).
                float bx = bx0 + prog * (0.30 + 0.06 * jtHash(vec2(fi, 3.0)));
                float by = by0 + prog * (0.52 + 0.04 * jtHash(vec2(fi, 5.0)));
                // Gentle wing-bob along the path so the flock feels alive.
                // GW_ENERGY scales the bob AMPLITUDE (calm<->lively), not its rate.
                by += 0.012 * eAmp * sin(mod(iTime, 7.0) * 2.0 + fi * 1.7);

                vec2 bc = vec2(bx * aspect, by);

                // Cheap reject: if this pixel is far from the bird center relative
                // to its on-screen size, the gaussian stroke is ~0 — skip jtBird.
                // GW_GLOW enlarges the soft stroke (the reject radius below uses
                // s, so it follows automatically); default 1.0 = authored size.
                vec2 rel = ap - bc;
                float s = mix(0.030, 0.006, prog) * GW_GLOW;
                if (dot(rel, rel) > (s * 4.0) * (s * 4.0)) continue;

                float mark = jtBird(rel, s);
                vec3 birdCol = vec3(0.95, 0.97, 1.00);   // soft off-white #f4f8ff
                // GW_DENSITY scales the flock's brightness/coverage (lusher >1).
                effect += birdCol * mark * fade * flockGate * 0.9 * GW_DENSITY;
            }
        }
    }

    // ===================== Phase 2 — 孤雲獨去閒 : the lone cloud drifts out ==
    // After the birds are gone, ONE soft cloud puff appears high in the sky and
    // drifts slowly LEFT → RIGHT, fading as it goes, until the sky is bare. It
    // is a small soft blob textured by fbm — idle and unhurried (閒).
    {
        // Phase-2 window: opens as birds finish, closes well before loop end so
        // the final third of the cycle is empty stillness (留白).
        float cloudGate = smoothstep(0.30, 0.38, ph) * smoothstep(0.70, 0.60, ph);
        // GATE: only inside the phase-2 window AND near the cloud's high band
        // (cy≈0.74) does the cloud contribute. Everything else skips the fbm.
        if (cloudGate > 0.0 && uv.y > 0.55 && uv.y < 0.92) {
            float p2 = smoothstep(0.30, 0.66, ph);       // 0 → 1 across phase 2
            // Drift left→right, high in the sky. Starts left-of-center, exits right.
            float cx = mix(0.22, 0.86, p2);
            // GW_ENERGY scales the cloud's vertical bob AMPLITUDE (calm<->lively),
            // not the drift rate — the lateral path is unchanged.
            float cy = 0.74 + 0.015 * eAmp * sin(mod(iTime, 11.0) * 0.5);   // gentle bob
            vec2 cc = vec2(cx * aspect, cy);

            // Soft elliptical body (much wider than tall) with fbm-broken edges so
            // it reads as a drifting wisp of cloud, not a disc. A faint trailing
            // tail to the LEFT (where it came from) emphasises lateral drift.
            // GW_GLOW widens the gaussian radii (multiplying the falloff
            // denominators softens/spreads the puff); default 1.0 = authored.
            vec2 d = (ap - cc);
            d.x *= 0.42;                                  // stretch horizontally
            float body = exp(-dot(d, d) / (0.0052 * GW_GLOW));
            // Soft trailing wisp behind the cloud (to its left), thinner + fainter.
            vec2 dt = (ap - cc) - vec2(-0.075, 0.004);
            dt.x *= 0.30;
            body += 0.5 * exp(-dot(dt, dt) / (0.0040 * GW_GLOW));
            // Cheap reject: where the blob is already ~0, skip the fbm texture.
            if (body > 0.0008) {
                // Texture: fbm modulation drifting with the cloud breaks the edges.
                float tex = 0.45 + 0.65 * jtFbm(vec2(uv.x * 7.0 - p2 * 2.0, uv.y * 7.0 + 4.0));
                body *= clamp(tex, 0.0, 1.4);
                // Fade in on arrival, fade out as it leaves (idle departure).
                float cloudFade = smoothstep(0.0, 0.18, p2) * (1.0 - smoothstep(0.72, 1.0, p2));

                vec3 cloudCol = vec3(0.92, 0.94, 1.00);  // soft luminous off-white
                // GW_DENSITY scales the cloud's presence/coverage (lusher >1).
                effect += cloudCol * body * cloudFade * cloudGate * 0.55 * GW_DENSITY;
            }
        }
    }

    // ---- MANDATORY composite : additive, luminous-on-dark, text legible ----
    effect = max(effect, vec3(0.0));

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (dusk, mountain rim,
    // birds and cloud alike) so the feeling reads at a glance — cold/bleak (-1)
    // through the authored dusk (0) to warm/tender (+1). Default 0 = identity.
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;
    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
