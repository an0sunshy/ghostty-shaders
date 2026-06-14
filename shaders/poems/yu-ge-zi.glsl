// 漁歌子 (Yú Gē Zǐ) — Fisherman's Song — 張志和 (Zhang Zhihe), Tang
//   西塞山前白鷺飛，桃花流水鱖魚肥。
//   "Before Xisai Mountain the white egrets fly;
//    peach blossoms drift on the stream where the mandarin fish grow fat."
//
// A wide quiet riverscape. Composited back to front:
//   - 西塞山 : a faint, mist-veiled distant mountain ridge low on screen,
//     rendered as a soft luminous rim along its silhouette (atmospheric
//     glow on the slope) rather than a heavy dark block, so the frame
//     stays dark and the center is free for text.
//   - 白鷺飛 (LEAD motion) : a single white egret GLIDES slowly left to
//     right in a shallow arc, passing in front of the mountain. Long
//     swept wings flap with a gentle sine bob; the whole bird is a
//     luminous white shape with a soft halo.
//   - 桃花流水 (secondary motion) : scattered blush-pink peach petals
//     DRIFT downstream — they fall toward the bottom of the frame on the
//     current, each rotating slightly and swaying as it floats past.
//   - a faint slate-green shimmer marks the stream surface low in the
//     frame, anchoring the water plane without lifting the dark center.
//
// Palette: egret white #f4f8ff, blush-pink petals #f6c5be,
//          slate-green water #16323c, charcoal sky #06070c.
//
// PERF: the expensive per-pixel work (multi-octave fbm for the mountain ridge
// and the water shimmer; the 14-petal drift loop; the egret) is each confined
// to a small region of the frame. Cheap region bounds gate every heavy block
// so the large dark expanse — most pixels — skips it entirely. Pixels that
// contributed ~0 still contribute ~0, so the look is unchanged.
//
// DIALS: four shared "feeling" knobs (defaults = authored look, identity):
//   GW_MOOD warms/cools the whole scene; GW_ENERGY scales motion AGITATION
//   (petal sway + wing-flap arc + a gust above default, not the clocks);
//   GW_DENSITY scales fill (petal coverage, water shimmer, mountain rim);
//   GW_GLOW scales every bloom radius and feathered edge for softness.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls.
//   GW_MOOD   : global warm/cool tone over the egret, petals, mountain & water.
//   GW_ENERGY : agitation of the lead motion (petal sway + the egret's wing
//               flap arc) and a gentle gust above default — NOT the clocks.
//   GW_DENSITY: how much the frame FILLS — petal coverage, water shimmer and
//               mountain rim strength scale with it (>1 lusher, <1 more 留白).
//   GW_GLOW   : bloom/softness of every glow radius and feathered edge.
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

float ygHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float ygNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = ygHash(i);
    float b = ygHash(i + vec2(1.0, 0.0));
    float c = ygHash(i + vec2(0.0, 1.0));
    float d = ygHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float ygFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * ygNoise(p); p *= 2.05; a *= 0.5; }
    return v;
}

// Soft round point glow in aspect-corrected space. Returns 0..1.
float ygGlow(vec2 p, vec2 c, float r) {
    float d = length(p - c);
    return exp(-d * d / max(r * r, 1e-4));
}

// 2x2 rotation.
mat2 ygRot(float a) {
    float s = sin(a), c = cos(a);
    return mat2(c, -s, s, c);
}

// One soft peach-blossom petal, centered at the origin in local space.
// A rounded teardrop (wide lobe, gently tapered base), feathered at the rim
// so it reads as a soft drifting petal — NOT a sharp-pointed star. `lp` is
// local coords already rotated / scaled to unit-ish size.
float ygPetal(vec2 lp) {
    // Teardrop radius: rounded over the top half (+y), tapering toward the
    // base (-y). A single smooth lobe, no radial spikes.
    float ang = atan(lp.x, lp.y);            // 0 at +y (top of petal)
    float taper = 1.0 - 0.32 * smoothstep(0.0, 3.14159265, abs(ang)); // narrow base
    float rim = 0.95 * taper;
    float r = length(lp);
    // Soft feathered fill from center out to the tapered rim.
    float body = smoothstep(rim, rim - 0.65, r);
    // Faint crease down the middle to hint at a folded petal.
    body *= 1.0 - 0.18 * exp(-pow(lp.x / 0.18, 2.0)) * smoothstep(0.0, 0.4, lp.y);
    return body;
}

// Distance from point p to the line segment a->b (all in the same space).
float ygSegDist(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}

// Egret silhouette in bird-local space `q` (already aspect-corrected, the
// bird centered at the origin, +x = direction of flight). `flap` in [-1,1]
// drives the wing dihedral. Returns a soft luminous 0..1 mask shaped like a
// long-winged wader: slender body + neck, two long swept wings forming a
// shallow M that opens (down-stroke) and lifts (up-stroke) with the flap.
float ygEgret(vec2 q, float flap) {
    // Wing geometry. Each wing is TWO segments — an inner arm (shoulder->wrist)
    // and an outer hand (wrist->tip) — with the wrist bent so the wing curves
    // like a real long-winged wader rather than a straight V. The wrist and
    // tip lift on the up-stroke (flap > 0) and lower/flatten on the down-stroke.
    float lift = flap;                         // -1 (down) .. +1 (up)
    float dih  = 0.018 + 0.030 * lift;         // tip height
    float wrist = 0.012 + 0.016 * lift;        // mid-wing (wrist) height
    float xWrist = 0.040, xTip = 0.090;        // horizontal reach
    vec2 shoulderL = vec2(-0.010, 0.004);
    vec2 shoulderR = vec2( 0.010, 0.004);
    vec2 wristL = vec2(-xWrist, wrist);
    vec2 wristR = vec2( xWrist, wrist);
    vec2 tipL   = vec2(-xTip,   dih);
    vec2 tipR   = vec2( xTip,   dih);
    // Inner arms (thicker) and outer hands (thinner, tapering to the tip).
    float armL  = ygSegDist(q, shoulderL, wristL);
    float armR  = ygSegDist(q, shoulderR, wristR);
    float handL = ygSegDist(q, wristL, tipL);
    float handR = ygSegDist(q, wristR, tipR);
    float arms  = smoothstep(0.013, 0.0, min(armL, armR));
    float hands = smoothstep(0.009, 0.0, min(handL, handR));
    float wings = max(arms, hands);
    // Slender body + forward-leaning neck (the egret flies neck-extended): a
    // short tapered segment along the flight axis, thicker at the breast.
    float dBody = ygSegDist(q, vec2(-0.016, -0.004), vec2(0.032, 0.004));
    float body = smoothstep(0.012, 0.0, dBody);
    return clamp(wings + body, 0.0, 1.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                 // host is top-origin: uv.y = 1 at top

    // Sample the terminal glyph layer with the UNFLIPPED coord.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // Aspect-correct so circular glows / petals stay round on any window.
    float aspect = iResolution.x / iResolution.y;
    vec2 ap = vec2(uv.x * aspect, uv.y);

    // Seamless looping clocks. Never feed raw iTime to fast oscillators.
    float tBird   = mod(iTime, 36.0);   // egret crossing period
    float tFlap   = mod(iTime, 1.6);    // wing flap (short, fast loop)
    float tStream = mod(iTime, 600.0);  // long, for petal phase variety

    vec3 effect = vec3(0.0);

    // ---- 西塞山 : faint distant mountain ridge, luminous rim only ----
    // A static ridge profile built from layered low-freq fbm. We draw only a
    // thin glowing band hugging the silhouette's TOP edge (mist catching the
    // last light on the slope) plus a very dim body fill, so most of the
    // mountain stays as dark as the sky and never washes the frame.
    //
    // PERF GATE: ridge height peaks at ~0.455 (0.24 base + 0.07 + 0.035 fbm
    // maxima + 0.11 hump), and the rim's `smoothstep(-0.015, ...)` zeroes the
    // contribution once uv.y exceeds ridge + 0.015. So every pixel with
    // uv.y >= 0.48 lies above the highest possible crest and gets nothing —
    // skip both fbm calls there. (The vast upper frame, where the text lives.)
    if (uv.y < 0.48) {
        // Ridge height as a function of x. Two octaves of smooth bumps give a
        // believable mountain outline that peaks left-of-center (Xisai). Kept
        // LOW so wide quiet space remains above for text.
        float rx = uv.x;
        float ridge = 0.24
                    + 0.07 * ygFbm(vec2(rx * 1.7 + 3.0, 0.0))
                    + 0.035 * ygFbm(vec2(rx * 4.3 + 8.0, 1.0));
        // A broad single hump so it reads as one mountain, tallest near x~0.30.
        ridge += 0.11 * exp(-pow((rx - 0.30) * 2.4, 2.0));
        float d = ridge - uv.y;            // >0 below the ridge line (mountain)
        // Crisp luminous rim hugging the silhouette edge — the readable feature.
        // GW_GLOW softens the rim's falloff (divide the tightness so the mist
        // veil spreads wider off the crest); default 1.0 keeps the authored 42.0.
        float rim = exp(-pow(max(d, 0.0) * (42.0 / GW_GLOW), 2.0))  // tight to the crest
                  * smoothstep(-0.015 * GW_GLOW, 0.002, d);         // only on mountain side
        // Barely-there interior haze: a thin veil just under the crest that
        // fades to pure dark within the body, so the mountain never washes the
        // lower frame. Falls off quickly with depth into the mass.
        float body = smoothstep(0.0, 0.015 * GW_GLOW, d) * exp(-max(d, 0.0) * 14.0) * 0.05;
        // Misty cool slate tint for the ridge.
        vec3 ridgeCol = vec3(0.28, 0.44, 0.50);
        vec3 rimCol   = vec3(0.46, 0.62, 0.66);
        // GW_DENSITY scales the ridge's presence (rim + haze) so a lusher dial
        // fills the lower frame more; default 1.0 leaves the authored strength.
        effect += (rimCol * rim * 0.20 + ridgeCol * body) * GW_DENSITY;
    }

    // ---- faint slate-green stream shimmer, low in the frame ----
    // Marks the water plane the petals drift on. A thin feathered band with a
    // slow horizontal shimmer; kept very dim so the dark center survives.
    //
    // PERF GATE: the band factor `smoothstep(0.20, 0.05, uv.y)` is exactly 0
    // for uv.y >= 0.20, so the whole contribution (and its fbm ripple) vanishes
    // there — gate the heavy fbm behind uv.y < 0.21.
    if (uv.y < 0.21) {
        float waterTop = 0.16;             // surface sits low
        float band = smoothstep(0.0, waterTop, uv.y) * smoothstep(0.20, 0.05, uv.y);
        float ripple = ygFbm(vec2(uv.x * 6.0 + tStream * 0.02, uv.y * 18.0));
        float shimmer = 0.45 + 0.55 * sin(uv.x * 22.0 + ripple * 5.0
                        + mod(iTime, 40.0) * 0.6);
        shimmer = clamp(shimmer, 0.0, 1.0);
        vec3 waterCol = vec3(0.16, 0.42, 0.40);   // slate-green #16323c lifted
        // GW_DENSITY scales the water plane's presence (lusher = more visible
        // stream surface); default 1.0 keeps the authored dim shimmer.
        effect += waterCol * band * (0.05 + 0.05 * shimmer) * GW_DENSITY;
    }

    // ---- 桃花流水 : peach petals drifting downstream (downward) ----
    // A fixed set of petals, each given a deterministic lane (x), fall speed,
    // size, and spin from its index hash. Vertical position wraps 1.15 -> -0.15
    // so petals continuously enter at the TOP of the drift band and exit at the
    // BOTTOM (downstream = toward screen bottom, the verified fall direction).
    //
    // PERF GATE: every petal's center py lands in (0.03, 0.45] and its visible
    // footprint (teardrop rim + soft halo) reaches at most ~4.5*size <= ~0.15
    // around the center. So the whole drift effect lives below uv.y ~ 0.5 —
    // skip the entire loop for the upper frame. Inside the band, each iteration
    // cheaply rejects petals whose footprint can't reach this pixel.
    const int NPETAL = 14;
    if (uv.y < 0.5) {
        for (int i = 0; i < NPETAL; i++) {
            float fi = float(i);
            float h1 = ygHash(vec2(fi, 1.0));
            float h2 = ygHash(vec2(fi, 7.0));
            float h3 = ygHash(vec2(fi, 13.0));

            // Lane and motion params.
            float laneX = h1;                          // 0..1 across the frame
            float fallSpd = 0.028 + 0.040 * h2;        // units/sec downward
            float size = 0.018 + 0.014 * h3;           // petal radius
            float spinSpd = (h3 - 0.5) * 1.6;          // slow rotation, either way
            float phase = h1 * 9.0 + h2 * 5.0;         // per-petal time offset

            // Vertical travel: descend through the drift band, wrap seamlessly.
            // Band spans roughly uv.y 0.10 .. 0.40 (low third of the frame).
            float yTop = 0.40, yBot = 0.08;
            float span = yTop - yBot;
            float prog = fract(phase * 0.13 + tStream * fallSpd / span);
            float py = yTop - prog * (span + 0.10) + 0.05;  // a touch of overscan
            // Gentle sway as it floats on the current. GW_ENERGY scales the sway
            // AMPLITUDE (not the rate), plus a shared lateral gust that grows
            // only above default — so the petals read calm<->lively on the
            // current rather than teleporting. eAmp = 1.0 at the default.
            float eAmp = 0.45 + 0.55 * GW_ENERGY;          // 1.0 at default
            float sway = 0.020 * eAmp * sin(mod(iTime, 29.0) * (0.5 + h2) + phase);
            float gust = 0.014 * max(GW_ENERGY - 1.0, 0.0)
                       * sin(mod(iTime, 31.0) * 0.5 + py * 4.0);
            float px = laneX + sway + gust;

            vec2 petalC = vec2(px * aspect, py);

            // Cheap bound: the petal body + halo fade to ~0 beyond ~4.5*size
            // from the center. The halo radius grows with GW_GLOW, so widen the
            // reject disc by the same factor (keeps the gate conservative when
            // GW_GLOW > 1). Squared compare avoids a sqrt.
            vec2 dC = ap - petalC;
            float reach = size * 4.5 * max(GW_GLOW, 1.0);
            if (dot(dC, dC) > reach * reach) continue;

            // Fade in/out at the band edges so petals don't pop.
            float edgeFade = smoothstep(0.0, 0.06, py - (yBot - 0.04))
                           * smoothstep(0.0, 0.06, (yTop + 0.06) - py);

            // Local coords, rotated by the petal's spin.
            float spin = spinSpd * mod(iTime, 60.0) + phase;
            vec2 lp = dC;
            lp = ygRot(spin) * lp;
            lp /= size;
            float petal = ygPetal(lp);

            // Soft blush-pink, uniform across the petal (no bright spike core),
            // plus a faint warm halo so it reads as a blossom catching light.
            // GW_GLOW widens the halo (softer, dreamier bloom); GW_DENSITY scales
            // the petal's overall presence so the drift band reads lusher or
            // sparser. Both default to 1.0 = the authored blossom.
            vec3 petalCol = vec3(0.96, 0.77, 0.74);        // #f6c5be blush
            float halo = ygGlow(ap, petalC, size * 1.6 * GW_GLOW) * 0.18;
            effect += petalCol * (petal * 0.46 + halo) * edgeFade * GW_DENSITY;
        }
    }

    // ---- 白鷺飛 : a single white egret gliding left to right (LEAD) ----
    // The bird crosses the frame in a shallow arc, riding above the mountain
    // ridge. Its long wings beat with a slow, deliberate egret flap. It is
    // visible on screen for most of the loop; only a brief moment at each end
    // is spent entering / leaving so the crossing feels continuous.
    {
        // Crossing progress 0..1 over tBird. Spend ~85% of the loop traversing
        // the visible frame and a short tail off-right before re-entering.
        float cross = tBird / 36.0;                 // 0..1
        float bx = mix(-0.12, 1.12, cross);         // off-left to off-right
        // Shallow arc: rises toward the middle of the crossing, descends at the
        // ends — a glide just above the ridge line ("before the mountain").
        float arc = 0.52 - 0.06 * sin(cross * 3.14159265);
        // Slow, deliberate wing beat: ~0.6 flaps/sec. One sine over a 1.6s loop.
        // GW_ENERGY scales the flap AMPLITUDE (how far the wings swing + the
        // matching body bob), not its rate — so low energy is a placid glide and
        // high energy a livelier beat. eAmp = 1.0 at the default (identity).
        float eAmp = 0.45 + 0.55 * GW_ENERGY;          // 1.0 at default
        float flap = sin(tFlap * (6.2831853 / 1.6)) * eAmp;   // -1..1 at default
        // The body bobs slightly opposite the wing dihedral (lift on down-stroke).
        float by = arc - 0.012 * flap;

        vec2 birdC = vec2(bx * aspect, by);
        vec2 q = ap - birdC;                        // bird-local (aspected)

        // PERF GATE: the egret silhouette spans at most ~0.09 horizontally and
        // its halo (ygGlow radius 0.09) is negligible beyond ~0.30. Pixels more
        // than ~0.32 from the bird centre receive nothing — skip the segment
        // distances and glow entirely. The bird occupies a tiny slice of frame.
        if (dot(q, q) < 0.32 * 0.32) {
            float birdShape = ygEgret(q, flap);
            // Soft luminous halo so the bird glows against the dark sky.
            // GW_GLOW widens it for a dreamier bloom; default 1.0 keeps 0.09.
            float halo = ygGlow(q, vec2(0.0), 0.09 * GW_GLOW) * 0.30;

            // Fade in/out only in the off-frame margins, so it's solid on screen.
            float onScreen = smoothstep(-0.12, -0.02, bx) * smoothstep(1.12, 1.02, bx);

            vec3 egretCol = vec3(0.95, 0.97, 1.00);     // glowing white #f4f8ff
            effect += egretCol * (birdShape * 1.05 + halo) * onScreen;
        }
    }

    // ---- MANDATORY composite : additive, luminous-on-dark, text legible ----
    effect = max(effect, vec3(0.0));

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (egret, petals,
    // mountain and water alike) so the feeling reads at a glance — cool/wistful
    // (-1) through the authored balance (0) to warm/spring-tender (+1). Default
    // 0 = identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;
    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
