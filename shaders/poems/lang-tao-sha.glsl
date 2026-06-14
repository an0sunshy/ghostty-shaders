// 浪淘沙·其七 — Waves Scouring the Sand, No. 7 (Liu Yuxi)
//   "八月濤聲吼地來，捲起沙堆似雪堆。"
//   August's tidal roar comes bellowing over the land,
//   rolling up sand-heaps like drifts of snow.
//
// The Qiantang tidal bore: ONE towering wall of white water surges in
// across a dark estuary, rears up and breaks at the peak flinging spray,
// then sucks back out — a surge-and-retreat loop. The wall is rendered as
// a turbulent, broken-topped front (not a clean ribbon): a tall body of
// churning foam whose ragged crest line advances left→right and rears as
// the surge builds. The open dark sky above the crest is kept clean for
// terminal text (留白).
//
// Composition (post-flip Shadertoy coords; uv.y=0 bottom, 1 top):
//   - Lower band: dim dark-teal sea plane with a faint surface ripple.
//   - A single advancing FOAM WALL: a steep leading face sweeping
//     left→right, foam churning behind it, its crest height riding a
//     surge-and-retreat envelope on mod(iTime,P). The crest edge is
//     fbm-displaced so the top reads as broken froth, not a sine curve.
//   - At the break peak the crest flings spray particles upward.
//   - Foam streaks roll along the shoreline at the very bottom.
//   - Upper region stays near-black sky for text.
//
// Palette: near-black sky #04080b, dark teal sea #0a2630,
// white-and-pale-cyan foam #d8f4ff.
//
// FLOAT-SAFETY: iTime is wrapped with mod() everywhere it drives fast
// oscillation; the surge runs on a single seamless period.
//
// FEELING DIALS: four neutral-default knobs (GW_MOOD / GW_ENERGY / GW_DENSITY /
// GW_GLOW) tune the mood. MOOD warms/cools the whole tide; ENERGY scales the
// surf's agitation (crest froth, ripple, spray throw) without changing rates;
// DENSITY makes the foam/spray/shore lusher or sparser; GLOW softens the foam
// lip, droplets and edges. All-default reproduces the authored look exactly.
//
// PERF: the heavy per-pixel work — three foam fbm calls, a 44-droplet spray
// loop, plus the crest/shore fbm — is GATED behind cheap region tests. The
// dark sky (most of the frame) and the empty water far from the wall skip
// the fbm and the spray loop entirely; pixels that contributed ~0 still do,
// so the gating is lossless. The spray loop is itself dormant except in the
// brief break window, and per-droplet tests skip columns far from the face.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls.
//   GW_MOOD   — global warm/cool tone over the whole tidal scene.
//   GW_ENERGY — agitation of the surf: crest froth, ripple, spray throw.
//   GW_DENSITY— how lush vs sparse the foam/spray/shore coverage reads.
//   GW_GLOW   — bloom/softness of the foam lip, droplets and soft edges.
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

float ltsHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 2D value noise (smoothstep-interpolated lattice).
float ltsNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = ltsHash(i);
    float b = ltsHash(i + vec2(1.0, 0.0));
    float c = ltsHash(i + vec2(0.0, 1.0));
    float d = ltsHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 5-octave fbm — churned-foam turbulence. Constant loop bound. Unchanged
// from the original; the cost win comes entirely from gating the CALLS to
// this function (and the spray loop) behind cheap region tests, so the dark
// sky and empty water never invoke it. That gating is bit-exact: pixels that
// contributed ~0 still do.
float ltsFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * ltsNoise(p);
        p = p * 2.02 + vec2(3.1, 1.7);
        a *= 0.5;
    }
    return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;

    // iChannel0 is the glyph layer only — sample with the unflipped coord.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    float aspect = iResolution.x / iResolution.y;

    // ---- Surge-and-retreat envelope --------------------------------------
    // One seamless loop. Phase t01 in [0,1): a fast asymmetric inrush (the
    // bore bellows in and rears) then a slower suck-back-out.
    const float PERIOD = 15.0;
    float t01 = mod(iTime, PERIOD) / PERIOD;
    // Inrush 0→1 over the first 40% (fast rear-up), retreat 1→0 over the
    // rest (slow drain). Each leg eased with smoothstep.
    float inrush  = smoothstep(0.0, 0.40, t01);
    float retreat = smoothstep(0.40, 1.0, t01);
    float surge   = clamp(inrush - retreat, 0.0, 1.0);  // 0 → 1 peak → 0
    // Sharpened drama curve: the wall sits low most of the loop and rears
    // hard near the peak.
    float surgeHard = surge * surge * (3.0 - 2.0 * surge);
    // Break window — the brief instant the reared wall topples and sprays.
    float breakPeak = smoothstep(0.78, 1.0, surge);

    // ---- Advancing wall front --------------------------------------------
    // The wall is a vertical band of foam whose LEFT face is a steep front
    // that sweeps from left to right as the surge inrushes (吼地來 — coming
    // over the land). frontX is the x-position of the leading face.
    float frontX = -0.20 + 1.30 * inrush;          // sweeps off-left → off-right
    // Distance behind the advancing face (water trails on the LEFT as the
    // wall advances right). The wall is a coherent mass concentrated just
    // behind the face, then tails off into calmer water further back.
    float dxBehind = frontX - uv.x;                 // >0 behind face, <0 ahead
    // faceProx: 0 ahead of the wall → rises right behind the steep face.
    float faceProx = smoothstep(0.0, 0.14, dxBehind);
    // mass: the wall is brightest just behind the face and tapers back over
    // ~0.45 of the frame, so it reads as ONE travelling mass, not a slab.
    float mass = faceProx * smoothstep(0.62, 0.10, dxBehind);
    float behind = clamp(dxBehind / 0.45, 0.0, 1.0);

    // ---- Crest line (ragged, fbm-displaced) ------------------------------
    // Base sea level low; crest rears with the hardened surge. The wall is
    // tallest right at the advancing face and tapers into the trailing body.
    float tF = mod(iTime, 100.0);

    // GW_ENERGY scales the AGITATION amplitude of the surf — how violently the
    // crest froths, the sea ripples and spray is flung — NOT the surge/scroll
    // RATES (those stay seamless on their mod() periods, so dragging the dial
    // reads as calm<->stormy rather than teleporting the wave). eAmp = 1.0 at
    // the default; eGust adds a little extra throw ONLY above default.
    float eAmp  = 0.45 + 0.55 * GW_ENERGY;          // 1.0 at default
    float eGust = max(GW_ENERGY - 1.0, 0.0);        // 0 at/below default
    float seaLevel = 0.16;
    float crestMax = 0.40;                           // reared wall height
    // Body height profile: rears at the face, eases down into the trailing
    // body so the top is a single arching front rather than a flat slab.
    float bodyProfile = mass * (0.65 + 0.35 * behind);
    // Ragged crest: low-freq fbm displaces the crest top so it reads as
    // broken froth flung up along the lip rather than a smooth curve. The
    // displacement scales with surgeHard, so when the wall sits flat
    // (surgeHard≈0) the fbm contributes nothing — skip it then.
    float ragged = 0.0;
    if (surgeHard > 0.001) {
        float crestNoise = ltsFbm(vec2(uv.x * aspect * 5.0 + tF * 0.6, 4.0)) - 0.5;
        ragged = crestNoise * 0.10 * surgeHard * eAmp;
    }
    float crestY = seaLevel + crestMax * surgeHard * bodyProfile + ragged;

    // ---- Foam body -------------------------------------------------------
    // Turbulent foam fills from the sea up to the crest line, brightest in a
    // band just under the crest (the breaking lip), churning live. The boil
    // scrolls upward (foam rolling up the face) and a finer layer scrolls
    // across for live turbulence.
    //
    // The foam exists only inside the travelling mass and below the crest
    // line. Everywhere else (the dark sky above, the empty water far from the
    // wall) foamBright is identically 0, so we gate the two foam fbm calls
    // behind a cheap region test. belowCrest is needed for the test, so we
    // compute crestY-relative masks first.
    float belowCrest = smoothstep(crestY + 0.03, crestY - 0.06, uv.y);
    float foamBright = 0.0;
    // wall: glows only within the travelling mass, blazing with surgeHard.
    float wall = mass * (0.30 + 1.00 * surgeHard);
    // Foam can only show where there is mass AND the pixel is below the crest.
    if (mass > 0.0008 && belowCrest > 0.0008) {
        vec2 foamP  = vec2(uv.x * aspect * 3.2, uv.y * 6.5 - tF * 0.9);
        float foamN = ltsFbm(foamP);
        float foamN2 = ltsFbm(vec2(uv.x * aspect * 6.5 + tF * 0.5, uv.y * 12.0 - tF * 1.5));
        float churn = mix(foamN, foamN2, 0.45);

        // Lip highlight: a bright froth band hugging the ragged crest line.
        // GW_GLOW widens this soft band — the wall's signature bloom — so the
        // breaking crest reads crisp (low) or dreamy/misty (high). The 0.085
        // feather radius scales with GLOW; GLOW=1 keeps it as authored.
        float lip = smoothstep(0.085 * GW_GLOW, 0.0, abs(uv.y - crestY)) * belowCrest;
        // Depth 0 at trough → 1 at lip. Near the lip the foam is nearly solid
        // white water; lower down it breaks into churned whitecaps. A narrow
        // threshold ramp near the lip avoids big dark holes in the wall face.
        float depth = smoothstep(seaLevel - 0.05, crestY, uv.y);
        // GW_DENSITY: lowering the whitecap threshold lets MORE of the churn
        // pass as foam (a lusher, more filled wall); raising it opens gaps for
        // 留白. The shift is a fraction of the authored range so density=1 keeps
        // the threshold exactly as authored.
        float foamThresh = mix(0.66, 0.30, depth) - (GW_DENSITY - 1.0) * 0.14;
        foamThresh = clamp(foamThresh, 0.05, 0.95);
        float foam = smoothstep(foamThresh, foamThresh + 0.16, churn) * belowCrest;
        // Solidity: blend the broken whitecaps toward a filled face near the
        // lip so the upper wall is a coherent sheet of white water.
        foam = mix(foam, belowCrest, depth * depth * 0.7);
        foam *= (0.28 + 0.72 * depth);
        // The wall glows only within the travelling mass and blazes with the
        // hardened surge so the reared crest is brightest at the peak.
        foamBright = foam * wall + lip * (0.55 + 1.15 * surgeHard) * mass;
    }

    // ---- Dark teal sea below --------------------------------------------
    // A calm dim teal plane under the foam, faint surface ripple so the
    // trough isn't dead flat. Additive, luminous-on-dark — stays dim.
    float seaMask = smoothstep(seaLevel + 0.11, seaLevel - 0.11, uv.y);
    // Ripple AMPLITUDE rides GW_ENERGY (still water at low energy, livelier
    // chop above) while the ripple RATE (tF*1.1) is untouched. The 0.05
    // modulation depth scales by eAmp, so the default leaves the sea glow
    // bit-identical (eAmp=1).
    float ripple = 0.5 + 0.5 * sin(uv.x * 14.0 + tF * 1.1 + uv.y * 6.0);
    float seaGlow = seaMask * (0.09 + 0.05 * eAmp * ripple);

    // ---- Spray particles off the breaking crest -------------------------
    // Droplets launched upward above the crest near the advancing face,
    // only visible at the break peak. Each rises on a parabola and fades on
    // a per-cell phase, giving flung spray at the top of the surge.
    //
    // The whole loop is dormant except in the brief break window
    // (breakPeak>0), and even then only matters in a vertical band reaching
    // from just under the crest to its max launch height. Gate the entire
    // 44-iteration loop on those cheap bounds, and skip individual droplets
    // whose column is far from the breaking face (nearFace≈0).
    float spray = 0.0;
    // Max launch height is (0.12+0.18)=0.30 above the crest; the droplet
    // Gaussians have radius < 0.02, so a band of [crestY-0.06, crestY+0.34]
    // bounds every visible droplet. crestY here uses the local ragged value.
    if (breakPeak > 0.0 && uv.y > crestY - 0.06 && uv.y < crestY + 0.34) {
        for (int i = 0; i < 44; i++) {
            float fi = float(i);
            float h  = ltsHash(vec2(fi, 7.0));
            // Columns scattered, biased toward the advancing face where the
            // wall is breaking.
            float px = fract(0.02 + h * 0.96);
            float faceDx = (px - frontX) * 2.2;          // signed dist to face
            float nearFace = exp(-(faceDx * faceDx));    // square via multiply
            // Columns far from the breaking face contribute ~0 — skip them.
            if (nearFace < 0.004) continue;
            float h2 = ltsHash(vec2(fi, 19.0));
            float h3 = ltsHash(vec2(fi, 41.0));
            // Per-particle staggered launch phase.
            float life = fract(mod(iTime, PERIOD) / PERIOD * 4.0 + h2);
            float rise = 4.0 * life * (1.0 - life);      // 0→1→0 arc
            // GW_ENERGY: spray is flung HIGHER and a touch WIDER when the surf
            // is wild, barely lifting off the lip when calm. launchH is an
            // AMPLITUDE (the rise RATE via `life` is unchanged), so eAmp=1 at
            // default keeps the throw exactly as authored; eGust adds extra
            // wind-blown scatter only above default.
            float launchH = (0.12 + 0.18 * h3) * breakPeak * nearFace * eAmp;
            float py = crestY + rise * launchH;
            // Wind-blown horizontal scatter increasing as it flies.
            float pxNow = px + (h2 - 0.5) * (0.12 + 0.10 * eGust) * rise;
            vec2 d = (uv - vec2(pxNow, py)) * vec2(aspect, 1.0);
            float dot2 = dot(d, d);
            // GW_GLOW softens each droplet (a larger Gaussian radius = dreamier
            // mist); the radius scales with GLOW^2 because it sits under dot2 in
            // the exponent. GLOW=1 keeps the authored droplet size.
            float dropletR = (0.00016 + 0.00028 * h) * (GW_GLOW * GW_GLOW);
            float drop = exp(-dot2 / dropletR);
            float fade = sin(life * 3.14159265);
            spray += drop * fade * breakPeak * nearFace;
        }
        // GW_DENSITY scales how much spray fills the air above the lip. The loop
        // count is fixed (a constant bound), so we scale the accumulated
        // coverage rather than the iteration count — density=1 is identity.
        spray = clamp(spray * GW_DENSITY, 0.0, 1.5);
    }

    // ---- Shoreline foam streaks (very bottom) ---------------------------
    // Thin bright foam rolling along the shore, scrolling sideways. Adds
    // life at the base without lifting the dark sky. Confined to uv.y<0.06,
    // so the shore fbm is gated to that thin band.
    float shore = 0.0;
    float shoreBand = smoothstep(0.06, 0.0, uv.y) * smoothstep(0.0, 0.02, uv.y);
    if (shoreBand > 0.0008) {
        float shoreN = ltsFbm(vec2(uv.x * aspect * 5.0 - tF * 0.7, 12.3));
        // GW_DENSITY widens the shore-foam coverage band (more streaks roll in)
        // by lowering its keep-threshold; density=1 leaves it at the authored
        // 0.55 edge.
        float shoreLo = clamp(0.55 - (GW_DENSITY - 1.0) * 0.18, 0.05, 0.84);
        shore = smoothstep(shoreLo, 0.85, shoreN) * shoreBand * (0.45 + 0.55 * surge);
    }

    // ---- Compose colors --------------------------------------------------
    vec3 foamCol  = vec3(0.847, 0.957, 1.0);         // #d8f4ff pale-cyan white
    vec3 seaCol   = vec3(0.039, 0.149, 0.188);       // #0a2630 dark teal
    vec3 sprayCol = vec3(0.92, 0.98, 1.0);           // near-white droplets

    vec3 effect = vec3(0.0);
    effect += seaCol  * seaGlow;
    effect += foamCol * foamBright;
    effect += foamCol * shore;
    effect += sprayCol * spray * 0.7;

    // Every channel of the additive effect must stay >= 0.
    effect = max(effect, 0.0);

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (sea, foam wall,
    // spray and shore alike) so the feeling reads at a glance — a cold storm
    // (-1) through the authored teal-and-white tide (0) to a warm-lit surf
    // (+1). Default 0 = identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;

    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}