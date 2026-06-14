// 望天門山 (Wàng Tiānménshān) — Gazing at Heaven's Gate Mountains — 李白 (Li Bai), Tang
//   兩岸青山相對出，孤帆一片日邊來。
//   "From both banks the green peaks come forth to meet me;
//    a lone sail draws near, out of the side of the sun."
//
// The river has cleaved a mountain in two, forming a gate. Because the
// viewer is gliding through on a boat, the twin cliffs seem to swing OUT
// toward the frame edges and grow — the famous 相對出 parallax illusion of
// peaks "coming forth." The scene composites, from back to front:
//   - a warm sun-glow low on the central horizon (日邊), the source of light,
//   - a tiny luminous SAIL point that emerges from the side of that glow and
//     eases INWARD and slightly UP through the gap, growing as it nears (孤帆
//     ... 來) — counter-motion to a receding sail: here it APPROACHES,
//   - a narrow river band threaded between the cliffs carrying downstream
//     glints that drift toward the BOTTOM of the frame (the current running
//     out of the gate toward the viewer),
//   - two dark jade-green cliff silhouettes meeting near center in a V-gate;
//     on a slow seamless loop they translate OUTWARD and scale UP, then ease
//     back — the peaks advancing as the boat moves through.
// A clean central column is kept clear of opaque rock so terminal glyphs read
// (留白); the effect starts from black and ADDS only luminous sun/sail/water —
// the dark cliffs are rendered by SUBTRACTING glow where rock occludes, never
// by washing the whole frame with color.
//
// Direction check (host renders upright, top of PNG = top of screen):
//   - river glints scroll toward the BOTTOM as iTime grows (current outflow);
//   - the sail drifts from the horizon glow UP-and-IN and grows (approaching);
//   - the cliffs slide outward toward both edges over the slow loop.
//
// Float-safety: the slow cliff loop and the sail's traverse use fract()/
// mod(iTime,P) phases (seamless for arbitrarily large iTime); every sin/cos
// is fed a mod(iTime, period) argument so nothing degrades as iTime grows.
//
// Palette: jade-dark peaks #094228, sun-gold glow #ffad47, white sail #f4f8ff,
//          blue-green water #11403c, deep sky #060a18.
//
// Perf: the per-pixel multi-octave fbm is concentrated in the cliff masses
// (ridge + gorge-wall waver, 5 fbm calls) and the river band (2 fbm calls).
// Both are GATED behind cheap region bounds: the upper sky / central text gap
// above the ridgelines runs no cliff fbm, and the river fbm runs only below
// the waterline. Pixels outside those regions contribute ~0 to the look, so
// the gates are lossless — they just stop computing noise where it is unused.
//
// Four "feeling" dials (GW_MOOD / GW_ENERGY / GW_DENSITY / GW_GLOW) ride on top:
// a global warm/cool tint, the gate-swing + water agitation amplitude, the
// water-glint + jade fill coverage, and the sun/sail bloom radii. All-default
// (0,1,1,1) reproduces the authored scene exactly.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls.
//   GW_MOOD    palette warmth : -1 cold/blue .. 0 neutral .. +1 warm tint over all
//   GW_ENERGY  motion agitation: 0.3 still .. 1 .. 2 lively — scales the gate
//              "coming forth" swing, the river glint strength + shimmer AMPLITUDE
//              (not the oscillator rates), so peaks/water never teleport
//   GW_DENSITY fill vs 留白    : 0.3 sparse .. 1 .. 1.8 lush — scales water-glint
//              coverage + the warm sun-wash + jade body fill
//   GW_GLOW    bloom/softness  : 0.6 crisp .. 1 .. 2.5 dreamy — scales sun/sail
//              glow radii and the soft silhouette/rim edge widths
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

// ---- hash / value-noise / fbm (inlined, house style; defined before use) ---
float tmHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float tmNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = tmHash(i);
    float b = tmHash(i + vec2(1.0, 0.0));
    float c = tmHash(i + vec2(0.0, 1.0));
    float d = tmHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float tmFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * tmNoise(p); p *= 2.05; a *= 0.5; }
    return v;
}

// Soft round point glow in aspect-corrected space. Returns 0..1.
float tmGlow(vec2 p, vec2 c, float r) {
    float d = length(p - c);
    return exp(-d * d / max(r * r, 1e-4));
}

// Ridge profile for a mountain silhouette: returns the surface height (uv.y)
// of a craggy ridgeline at horizontal position x. `peak` is the summit
// height, `base` the foot height, `freq` the crag frequency, `seed` a phase.
// The ridge is highest near `xPeak` and falls away to either side, with fbm
// roughness layered on so it reads as rock, not a smooth hump.
float tmRidge(float x, float xPeak, float peak, float base, float freq, float seed) {
    // Distance from this cliff's summit column, normalized.
    float d = abs(x - xPeak);
    // Broad triangular fall-off from summit to foot.
    float hump = peak - (peak - base) * smoothstep(0.0, 0.62, d);
    // Craggy detail: two octaves of fbm, stronger near the summit.
    float crag = (tmFbm(vec2(x * freq + seed, seed * 1.7)) - 0.5) * 0.16;
    crag += (tmFbm(vec2(x * freq * 2.3 + seed * 3.1, 9.0)) - 0.5) * 0.07;
    return hump + crag * smoothstep(0.62, 0.05, d);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                 // host is top-origin: uv.y = 1 at top

    // Sample the terminal glyph layer with the UNFLIPPED coord.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // Aspect-correct so circular glows stay round on any window shape.
    float aspect = iResolution.x / iResolution.y;
    vec2 ap = vec2(uv.x * aspect, uv.y);

    // Seamless looping clocks. Never feed raw iTime to fast oscillators.
    float tGate  = mod(iTime, 26.0);   // the slow "coming forth" gate loop
    float tSail  = mod(iTime, 22.0);   // the sail's traverse through the gap
    float tFlow  = mod(iTime, 18.0);   // river current outflow

    vec3 effect = vec3(0.0);

    // Horizon where river meets the far light. Kept LOW (lower third) so the
    // luminous focus — sun-glow, sail, water glints — sits beneath the bulk of
    // the terminal text, leaving the upper-center gap dark for 留白.
    float horizon = 0.30;

    // ---- gate "breathing" : the 相對出 parallax advance --------------------
    // A single slow phase in [0,1) drives how far the cliffs have slid OUT and
    // grown. Ease-in/ease-out (smooth triangle) so the advance feels like a
    // boat gliding, then a gentle reset. `adv` 0 → peaks met near center,
    // 1 → peaks swung out toward the edges and scaled up.
    float gp = tGate / 26.0;                      // 0..1 seamless
    float tri = 1.0 - abs(2.0 * gp - 1.0);        // 0→1→0 triangle
    float adv = smoothstep(0.0, 1.0, tri);        // eased advance 0..1
    // GW_ENERGY scales the AMPLITUDE of the "coming forth" swing — how far the
    // peaks slide out and grow each loop — NOT the loop rate, so dialing energy
    // reads as a calmer / livelier glide rather than teleporting the cliffs.
    // The eased phase still starts and ends at 0 (peaks met near center), so the
    // resting pose is shared across all energies; only the excursion changes.
    // Default 1.0 leaves `adv` exactly as authored (eAmp = 1.0).
    float eAmp = 0.45 + 0.55 * GW_ENERGY;         // 1.0 at default
    adv = clamp(adv * eAmp, 0.0, 1.0);
    // Cliff summit columns translate outward from the center as adv grows.
    float spread = mix(0.045, 0.140, adv);        // gap half-width at summit
    float grow   = mix(1.00, 1.18, adv);          // vertical scale of peaks

    // Left and right cliff summit x-positions (in uv.x space).
    float leftPeakX  = 0.5 - 0.18 - spread;
    float rightPeakX = 0.5 + 0.18 + spread;

    // ---- 日邊 : warm sun-glow low on the central horizon -------------------
    // The light source the sail emerges from. Sits in the gap, just at the
    // waterline. Kept compact so it is a glow on the horizon, not a wash.
    {
        vec2 sunC = vec2(0.5 * aspect, horizon + 0.010);
        // Gentle breathing of the glare.
        float breath = 0.86 + 0.14 * sin(mod(iTime, 37.0) * 0.21);
        // Compact disc + halo. The bloom is deliberately small and the whole
        // glow is biased DOWNWARD (it only blooms onto the water, not up into
        // the dark text gap) by gating the upward half.
        // GW_GLOW scales the sun's bloom RADII — softer/dreamier (>1) or a
        // crisper disc (<1). Default 1.0 keeps the authored radii.
        float core = tmGlow(ap, sunC, 0.045 * GW_GLOW);
        float halo = tmGlow(ap, sunC, 0.105 * GW_GLOW) * 0.45;
        float bloom = tmGlow(ap, sunC, 0.190 * GW_GLOW) * 0.12;
        // Suppress the part of the glow that reaches UP past the horizon into
        // the text gap; keep the full glow below the waterline.
        float upGate = mix(0.30, 1.0, smoothstep(0.10, -0.02, uv.y - horizon));
        vec3 sunCol  = vec3(1.00, 0.68, 0.30);    // sun-gold #ffad47
        vec3 haloCol = vec3(1.00, 0.78, 0.45);
        effect += (haloCol * core * 0.9 + sunCol * halo + sunCol * bloom) * breath * upGate;
        // A low warm sheen on the water directly below the glare, confined to a
        // narrow central strip so the flanks stay dark and the side columns clear.
        float belowSun = smoothstep(0.0, 0.16, horizon - uv.y);
        float strip = smoothstep(0.16, 0.0, abs(uv.x - 0.5));
        float wash = smoothstep(0.14, 0.0, horizon - uv.y);
        // GW_DENSITY also tunes the warm sun-sheen coverage on the water below
        // the glare (more fill = lusher horizon). Default 1.0 = authored.
        effect += sunCol * belowSun * strip * wash * 0.10 * breath * GW_DENSITY;
    }

    // ---- river current : downstream glints drifting toward the BOTTOM ------
    // Below the horizon, a narrow band of water threaded through the gate.
    // A downward-scrolling fbm makes bright filaments slide toward the bottom
    // (the current running out of the gate toward the viewer). Confined to a
    // central channel so the flanks stay dark for text.
    {
        float water = smoothstep(0.0, 0.03, horizon - uv.y);   // 1 below horizon
        if (water > 0.0) {
            // Channel narrows toward the horizon (perspective) and is centered.
            float depthBelow = horizon - uv.y;                 // 0..~0.44
            float chanHalf = 0.085 + 0.55 * depthBelow;        // widens toward us
            float channel = smoothstep(chanHalf, chanHalf * 0.45, abs(uv.x - 0.5));
            // The channel is the only place water glints contribute; outside it
            // the fbm is multiplied to ~0. Skip the two noise calls there.
            if (channel > 0.0) {
                // Downward scroll: subtract a growing offset from the v coordinate
                // so the noise pattern moves toward the bottom as time advances.
                float scroll = fract(tFlow * (1.0 / 18.0)) * 2.4;
                float fy = uv.y * 9.0 + scroll;                // +scroll => moves down
                float cur = tmFbm(vec2(uv.x * 7.0, fy));
                float glint = smoothstep(0.62, 0.95, cur);
                // A second faster layer for sparkle, also scrolling down.
                float scroll2 = fract(tFlow * (1.0 / 18.0) * 1.7) * 3.0;
                float spark = tmFbm(vec2(uv.x * 13.0 + 4.0, uv.y * 16.0 + scroll2));
                glint += smoothstep(0.80, 0.98, spark) * 0.6;
                // Water tints from warm (near the sun) to cool blue-green further
                // down / out toward the banks.
                vec3 warmW = vec3(0.55, 0.62, 0.42);
                vec3 coolW = vec3(0.12, 0.40, 0.40);          // blue-green #11403c
                float warmth = smoothstep(0.18, 0.0, depthBelow) * smoothstep(0.10, 0.0, abs(uv.x - 0.5));
                vec3 wCol = mix(coolW, warmW, warmth);
                // GW_DENSITY scales how much the water glints FILL the channel —
                // >1 a busier, lusher current, <1 sparser glints / more 留白.
                // Default 1.0 keeps the authored strength.
                effect += wCol * glint * channel * water * 0.30 * GW_DENSITY;
            }
        }
    }

    // ---- 孤帆一片日邊來 : a lone sail emerging from the sun, drawing near ----
    // The sail starts at the side of the sun-glow on the horizon and eases
    // INWARD-and-UP through the gap, growing as it approaches. Seamless loop:
    // it appears small from the right side of the glare, crosses toward center
    // as it nears, then fades and resets. Because it APPROACHES, it grows and
    // rises slightly off the horizon (counter to a receding sail).
    {
        float sp = tSail / 22.0;                  // 0..1 seamless
        // Visible only across most of the loop; fade in at the sun, fade out
        // as it would pass the viewer. journey 0..1 is the eased traverse.
        float journey = smoothstep(0.0, 1.0, sp);
        // Path: emerges from the SIDE of the sun (right of center, on the
        // horizon) and moves toward center, rising as it nears so it clears
        // the sun's glare and reads as a separate, approaching point.
        float sailX = mix(0.5 + 0.090, 0.5 + 0.012, journey);
        float sailY = mix(horizon + 0.008, horizon + 0.110, journey);
        // Grows as it approaches.
        float sailScale = mix(0.006, 0.024, journey);
        // Brightness: faint as it leaves the glare, brightest mid-journey,
        // easing off at the end of the loop so the reset is invisible.
        float appear = smoothstep(0.0, 0.10, sp);
        float vanish = smoothstep(1.0, 0.86, sp);
        float sailBright = appear * vanish;
        vec2 sailC = vec2(sailX * aspect, sailY);
        // The sail body: a small upright triangle-ish point of cold white.
        float pt = tmGlow(ap, sailC, sailScale);
        // GW_GLOW softens the sail's aura (its bloom halo), leaving the discrete
        // core size driven by the approach animation. Default 1.0 = authored.
        float pt2 = tmGlow(ap, sailC, sailScale * 2.4 * GW_GLOW) * 0.4;   // soft aura
        // Sharpen the core a little so it reads as a discrete sail, not a blob.
        float core = smoothstep(0.30, 1.0, pt);
        vec3 sailCol = vec3(0.95, 0.97, 1.00);    // white sail #f4f8ff
        effect += sailCol * (core * 0.85 + pt2) * sailBright;
        // A faint wake glint trailing below the sail on the water.
        float wakeY = sailY - 0.018;
        if (uv.y < sailY) {
            float wk = tmGlow(ap, vec2(sailX * aspect, wakeY), sailScale * 1.6);
            effect += vec3(0.70, 0.80, 0.85) * wk * 0.20 * sailBright;
        }
    }

    // ---- 兩岸青山 : the two cliff silhouettes forming the gate -------------
    // Each cliff is a dark jade mass. Rather than ADD a sky color, we render
    // the rock by OCCLUSION + a faint jade body: a fragment is rock when it is
    // (a) below that side's ridgeline AND (b) outside that side's inner gorge
    // wall. The gorge wall is a SLOPED line — the gap is narrow at the horizon
    // and opens DOWNWARD, so the cliffs meet in a true V "gate" that the river
    // pours out of, instead of a rectangular slot. The center stays open above
    // and through the gap → the text column reads cleanly.
    float baseH = horizon - 0.02;             // foot a touch below the water
    float peakH = horizon + mix(0.30, 0.34, adv) * grow;
    // Cheap V-shaped vertical bound: every term in this block is gated on
    // `belowL/R` (rock/body/inner-rim) or `crestL/R` (crest rim), and all of
    // those vanish above their cliff's ridgeline. The true ridgeline is
    // `hump + crag`; the smooth `hump` (no fbm) is an exact upper bound on the
    // non-crag part, so `max(humpL,humpR) + margin` upper-bounds the highest
    // pixel any cliff term can reach. Computing the two humps is pure arithmetic
    // (no noise). Above that V we skip the 5 fbm calls — which clears not just
    // the flat top of the frame but the large dark triangles above the central
    // gap and above the outer flanks (where humps fall to baseH). The peak
    // (ridge - hump) over all advance phases and both cliffs is ~0.017; adding
    // the 0.016 crest soft edge gives a true requirement of ~0.033, so the 0.07
    // margin keeps a ~2x safety cushion and is still lossless (verified by a
    // zero-diff A/B render).
    float humpL = peakH - (peakH - baseH) * smoothstep(0.0, 0.62, abs(uv.x - leftPeakX));
    float humpR = peakH - (peakH - baseH) * smoothstep(0.0, 0.62, abs(uv.x - rightPeakX));
    if (uv.y < max(humpL, humpR) + 0.07) {
        float ridgeL = tmRidge(uv.x, leftPeakX,  peakH, baseH, 5.0, 2.0);
        float ridgeR = tmRidge(uv.x, rightPeakX, peakH, baseH, 5.0, 17.0);

        // Inner gorge walls (the V). At the ridge top the two walls nearly
        // touch (gap = topGap); descending toward the foot they splay apart by
        // `spread`-driven slope, so the opening widens downward like a gorge
        // mouth. wallL is the right edge of the left cliff; wallR the left edge
        // of the right cliff. A small fbm waver keeps the wall craggy.
        float topGap   = 0.018 + 0.5 * spread;    // half-gap at the summit line
        float footGap  = 0.085 + 1.05 * spread;   // half-gap down at the foot
        // 0 at peak height → 1 at foot; clamps outside the cliff band.
        float drop = clamp((peakH - uv.y) / max(peakH - baseH, 1e-4), 0.0, 1.0);
        float halfGap = mix(topGap, footGap, drop);
        float wallWav = (tmFbm(vec2(uv.y * 9.0 + 31.0, 5.0)) - 0.5) * 0.018;
        float wallL = 0.5 - halfGap + wallWav;    // inner face of left cliff
        float wallR = 0.5 + halfGap - wallWav;    // inner face of right cliff

        // Rock masks. Below the ridge AND outside (away from center of) the
        // gorge wall for each side. Soft edges so silhouettes don't pixel-step.
        float belowL = smoothstep(0.012, -0.012, uv.y - ridgeL);
        float belowR = smoothstep(0.012, -0.012, uv.y - ridgeR);
        float outerL = smoothstep(0.010, -0.010, uv.x - wallL); // 1 left of wallL
        float outerR = smoothstep(0.010, -0.010, wallR - uv.x); // 1 right of wallR
        float rockL = belowL * outerL;
        float rockR = belowR * outerR;
        float rock = clamp(rockL + rockR, 0.0, 1.0);

        // Subtractive occlusion: rock blocks the luminous gap glow behind it.
        effect *= (1.0 - rock * 0.97);

        // Sunward-face lighting term: each cliff's inner face (toward the gap /
        // the sun) catches the warm light; the outer flanks fall to jade-black.
        float litL = smoothstep(0.5 - 0.26, 0.5 - 0.02, uv.x); // brighter toward gap
        float litR = smoothstep(0.5 + 0.26, 0.5 + 0.02, uv.x);

        // Jade body fill so the masses read as green-black ROCK, not void.
        // Brightest just inside the sunward face and fading up the slope and
        // out toward the dark flanks. Confined to the rock; never lifts center.
        vec3 jadeDeep = vec3(0.02, 0.11, 0.075);  // jade-black #094228 dimmed
        vec3 jadeLit  = vec3(0.10, 0.30, 0.17);   // sun-touched jade
        float faceL = smoothstep(0.06, 0.0, abs(uv.x - wallL)); // near inner face
        float faceR = smoothstep(0.06, 0.0, abs(uv.x - wallR));
        float upFadeL = smoothstep(0.16, 0.0, ridgeL - uv.y);   // brighter near crest
        float upFadeR = smoothstep(0.16, 0.0, ridgeR - uv.y);
        vec3 bodyColL = mix(jadeDeep, jadeLit, litL);
        vec3 bodyColR = mix(jadeDeep, jadeLit, litR);
        // GW_DENSITY scales the jade body fill so the masses read lusher (>1) or
        // thinner / more void (<1). Default 1.0 keeps the authored 0.9 weight.
        effect += bodyColL * rockL * (0.35 + 0.65 * faceL) * (0.4 + 0.6 * upFadeL) * 0.9 * GW_DENSITY;
        effect += bodyColR * rockR * (0.35 + 0.65 * faceR) * (0.4 + 0.6 * upFadeR) * 0.9 * GW_DENSITY;

        // Bright jade rim-light along the inner gorge faces — a thin lit edge
        // where sunlit rock meets the glowing gap, making the silhouettes pop.
        // GW_GLOW widens the lit rim/crest feathers — a soft, dreamy glow along
        // the gorge faces (>1) or a crisp hairline (<1). Default 1.0 = authored.
        float rimL = smoothstep(0.013 * GW_GLOW, 0.0, abs(uv.x - wallL)) * belowL * litL;
        float rimR = smoothstep(0.013 * GW_GLOW, 0.0, abs(uv.x - wallR)) * belowR * litR;
        // And a softer rim along the crest ridgelines.
        float crestL = smoothstep(0.016 * GW_GLOW, 0.0, abs(uv.y - ridgeL)) * outerL * litL;
        float crestR = smoothstep(0.016 * GW_GLOW, 0.0, abs(uv.y - ridgeR)) * outerR * litR;
        vec3 jadeRim = vec3(0.22, 0.66, 0.40);    // bright jade rim
        vec3 warmRim = vec3(0.70, 0.55, 0.28);    // warm where it faces the sun
        // Rim shimmer: GW_ENERGY scales the shimmer AMPLITUDE (how much the lit
        // edge pulses), not its rate. eAmp = 1.0 keeps the authored 0.15 swing.
        float shim = 0.85 + 0.15 * eAmp * sin(mod(iTime, 29.0) * 0.4 + uv.y * 10.0);
        vec3 rimCol = mix(jadeRim, warmRim, 0.45);
        effect += rimCol * (rimL + rimR) * 0.7 * shim;
        effect += rimCol * (crestL + crestR) * 0.45 * shim;
    }

    // ---- MANDATORY composite : additive, luminous-on-dark, text legible ----
    effect = max(effect, vec3(0.0));

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (sun-glow, sail,
    // water and jade rock alike) so the feeling reads at a glance — cold/austere
    // (-1) through the authored jade-and-gold (0) to warm/tender (+1). Default 0
    // = identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;
    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}