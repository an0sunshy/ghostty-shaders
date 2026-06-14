// 白雪歌送武判官歸京 (Báixuě Gē) — Song of White Snow, Cen Shen.
//   忽如一夜春風來，千樹萬樹梨花開。
//   "As if overnight a spring wind came, and ten-thousand pear trees
//    burst into blossom."
//
// Frontier dawn over a near-black indigo sky. A few faint diagonal boughs
// sweep across the frame; clustered along them, procedural pear-blossom
// nodes IGNITE OPEN in staggered waves — each a feathered, irregular white
// clump that scales from a spark to a soft bloom with a cool blush halo,
// then settles to a low ember. A slow wind shears the whole field so the
// blooms lean and quiver as one, and a few stray flakes peel off the boughs
// and drift DOWN. Heavy dark negative space between the arcs keeps the
// center legible — the snow IS the pear-blossom, luminous on near-black.
// Additive, luminous-on-dark; text passes through.
//
// Palette: deep indigo #0a1024 ground (host background), silver-white
// #f4f8ff blossom core, faint blush #f6c5be in the halo.
//
// Four feeling dials (neutral at default, so all-default = authored look):
//   GW_MOOD    global warm/cool tone over the whole field
//   GW_ENERGY  wind-shear AGITATION (sway/flake-wander amplitude, not rate)
//   GW_DENSITY blossom-field coverage + stray-flake count (留白 vs laden)
//   GW_GLOW    bloom/softness of the petal clumps, bough line and flakes

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls.
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

float bxHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 2D value noise + 3-octave fbm — feathers the bloom edges and gives the
// branch glow a crusted, uneven snow texture rather than a clean line.
float bxNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = bxHash(i);
    float b = bxHash(i + vec2(1.0, 0.0));
    float c = bxHash(i + vec2(0.0, 1.0));
    float d = bxHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float bxFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 3; i++) { v += a * bxNoise(p); p = p * 2.1 + 5.3; a *= 0.5; }
    return v;
}

// Bloom envelope over the shared loop, offset per node by `phase` ∈ [0,1).
// A blossom is dark, then IGNITES open fast, holds, eases down, and keeps a
// low resting ember so opened blooms don't blink fully off. Returned in
// [0,1]; `openAmt` reports how far the disk has scaled open (for radius).
float bloomEnv(float phase, out float openAmt) {
    float rise   = smoothstep(0.0, 0.10, phase);   // quick ignition
    float settle = smoothstep(0.85, 0.32, phase);  // ease back down
    float pop = rise * settle;
    pop = pop * pop * (3.0 - 2.0 * pop);            // smooth the peak
    openAmt = rise;                                 // disk stays open after igniting
    float ember = 0.16 * rise;                      // resting glow
    return max(pop, ember);
}

// One feathered pear-blossom clump centred at the origin in aspect-corrected
// local coords scaled to ~1 at the bloom edge. fbm wobble breaks the circle
// into irregular petals so it reads as crusted blossom, not a round lamp.
// `seed` decorrelates the wobble per node. Returns intensity (>= 0).
float petalClump(vec2 lp, float open, float seed) {
    float r = length(lp);
    // Radial petal modulation: a few lobes whose phase/strength vary by seed,
    // wobbled further by fbm so no two clumps share a silhouette.
    float ang = atan(lp.y, lp.x);
    float lobes = floor(5.0 + 2.0 * fract(seed * 7.3));   // 5..6 soft petals
    float petal = 0.5 + 0.5 * cos(ang * lobes + seed * 6.2831);
    float wob = bxFbm(lp * 2.2 + seed * 19.0);
    // Gentle petal modulation — feathered pear-blossom clump, not a hard
    // snow crystal. Low lobe amplitude keeps the silhouette round-ish.
    float edge = 0.66 + 0.16 * petal + 0.14 * (wob - 0.5);
    // Disk scales open with the ignition; before opening it's a tiny spark.
    float grow = mix(0.30, 1.0, open);
    // GW_GLOW: dividing the local radius widens every soft edge — the feathered
    // core and the blush halo bloom larger/dreamier (>1) or pull crisp (<1).
    // GW_GLOW=1 leaves the authored radii untouched.
    float rr = r / (grow * GW_GLOW);
    float core = smoothstep(edge, edge * 0.25, rr) * 0.60;  // feathered core
    float halo = smoothstep(1.30, 0.45, rr) * 0.30;         // cool blush halo
    return core + halo;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;

    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    float aspect = iResolution.x / iResolution.y;

    // Shared bloom clock — wrapped so huge iTime never breaks the loop.
    // BLOOM_P is the full ignite→settle period; each node phase-offsets
    // within it so bursts ripple across the boughs in staggered waves.
    const float BLOOM_P = 11.0;
    float clock = mod(iTime, BLOOM_P) / BLOOM_P;            // 0..1 loop

    // Low wind shear: the whole field leans and quivers on a slow, seamless
    // sine. Two wrapped frequencies combine so the sway never reads as a
    // single mechanical wobble. Stronger toward the top (branch tips).
    float w1 = sin(mod(iTime, 18.84955) * 0.3333);          // period 6π/0.333
    float w2 = sin(mod(iTime, 25.13274) * 0.5 + 1.7);
    // GW_ENERGY scales the AGITATION of the wind shear (sway/flake-wander
    // amplitude), NOT the oscillator rates — so dialing it reads as calm<->gusty
    // weather instead of teleporting blooms. `eAmp`=1.0 at the default, and an
    // extra slow gust grows ONLY above default. GW_ENERGY=1 keeps the authored sway.
    float eAmp = 0.45 + 0.55 * GW_ENERGY;
    float windGust = sin(mod(iTime, 37.69911) * 0.1667 + 0.9) * 0.6 * max(GW_ENERGY - 1.0, 0.0);
    float wind = (w1 * 0.7 + w2 * 0.3) * eAmp + windGust;

    // ----- Boughs: a few faint diagonal arcs sweeping the frame. Along each
    // arc sits a dense run of clustered blossom nodes plus a faint crusted
    // glow line tying them to the branch. Constant loop bounds for portability.
    const int NB_ARCS = 3;
    const int NODES_PER_ARC = 14;

    vec3 coreCol  = vec3(0.957, 0.973, 1.0);   // silver-white #f4f8ff
    vec3 bloomCol = vec3(0.965, 0.773, 0.741); // faint blush  #f6c5be

    float coreAccum = 0.0;   // white blossom core
    float haloAccum = 0.0;   // blush halo
    float lineAccum = 0.0;   // crusted bough glow

    for (int a = 0; a < NB_ARCS; a++) {
        float fa = float(a);
        float ha = bxHash(vec2(fa, 3.1));

        // Arc geometry. Each arc sweeps the frame on a gentle diagonal,
        // bowed by a quadratic term, with the arcs stacked into bands so
        // wide dark gaps (留白) remain between boughs and across the center.
        float yBase = 0.16 + 0.66 * (fa + 0.5) / float(NB_ARCS);  // stacked bands
        yBase += (ha - 0.5) * 0.05;
        float slope = mix(-0.20, 0.20, bxHash(vec2(fa, 7.7)));     // diagonal tilt
        float bow   = mix(-0.12, 0.12, bxHash(vec2(fa, 11.3)));    // curve bend

        // Arc centre at THIS pixel's column — the spine every node clusters
        // around. Computed once so the rest of the arc can be cheaply gated.
        float xrel = uv.x - 0.5;
        float yArc = yBase + slope * xrel + bow * xrel * xrel * 4.0;

        // REGION GATE (lossless): blossom nodes sit on the spine with only
        // small x/y jitter, and each clump fades out within ~2·sz (≤0.104) of
        // its centre. Over the ±0.064-uv x-window a node can reach this pixel,
        // the spine shifts ≤~0.013, and node jitter adds ≤0.0225 — so any node
        // able to brighten this pixel lies within 0.16 of yArc. Pixels in the
        // wide dark negative space between boughs fall outside that band and
        // skip the entire 14-node run (its hashes, envelopes and fbm clumps),
        // which is where the per-pixel cost lived.
        if (abs(uv.y - yArc) < 0.16) {
            for (int n = 0; n < NODES_PER_ARC; n++) {
                float fn = float(n);
                float t = (fn + 0.5) / float(NODES_PER_ARC);       // 0..1 along arc

                // Node centre on the bowed diagonal, in uv space.
                vec2 c;
                c.x = t;
                c.y = yBase + slope * (t - 0.5) + bow * (t - 0.5) * (t - 0.5) * 4.0;

                // Per-node jitter so the run reads as a natural scatter of buds,
                // not a regular bead string.
                float hn = bxHash(vec2(fa * 13.0 + fn, 5.5));
                float hn2 = bxHash(vec2(fa * 5.0 + fn * 2.3, 9.1));
                c.x += (hn - 0.5) * 0.055;
                c.y += (hn2 - 0.5) * 0.045;

                // Wind shear pushes nodes sideways (more near the top).
                c.x += wind * 0.028 * smoothstep(0.0, 1.0, c.y);

                // Staggered ignition: each node offset in the shared loop. The
                // offset trends with t so the burst sweeps ALONG the bough, with
                // a hash jitter so it isn't a clean marching wave.
                float off = fract(t * 1.3 + hn * 0.55 + fract(ha * 4.3));
                float phase = fract(clock + off);

                float open;
                float env = bloomEnv(phase, open);
                // Skip cost where this node is fully dark.
                if (env > 0.003) {
                    // Per-node size jitter; some buds bigger than others.
                    float sz = mix(0.026, 0.052, fract(hn * 31.7));
                    vec2 lp = (uv - c) * vec2(aspect, 1.0) / sz;
                    // Cheap bounding reject — far outside this clump contributes ~0.
                    // Scaled by GW_GLOW² so a widened halo isn't clipped; at the
                    // default (GW_GLOW=1) this is the authored 4.0 threshold.
                    if (dot(lp, lp) < 4.0 * GW_GLOW * GW_GLOW) {
                        float b = petalClump(lp, open, hn + fa * 0.37) * env;
                        coreAccum += b;
                        haloAccum += b * 0.7;
                    }
                }
            }
        }

        // Faint crusted-snow glow along the whole bough — a thin, broken line
        // that ties the blossoms to a branch. Distance to the bowed diagonal.
        float yArcLine = yArc + wind * 0.028 * smoothstep(0.0, 1.0, yArc); // shear line too
        float dLine = abs(uv.y - yArcLine);
        // The line glow lives within ≤0.015 of the spine; outside a small band
        // it is identically zero, so the crust fbm (the other per-pixel fbm
        // call) need only run for pixels hugging the branch.
        if (dLine < 0.02 * GW_GLOW) {
            float crust = bxFbm(vec2(uv.x * 9.0 + fa * 3.0, yBase * 20.0));
            // GW_GLOW widens the crusted-line soft edge so the bough glow softens
            // (>1) or pulls to a crisp hairline (<1). GW_GLOW=1 = authored width.
            float lineGlow = smoothstep((0.009 + crust * 0.006) * GW_GLOW, 0.0, dLine);
            // Only where snow has "crusted" along the branch, and fading at the
            // arc ends so lines never hit the frame edges.
            lineGlow *= smoothstep(0.0, 0.12, uv.x) * smoothstep(1.0, 0.88, uv.x);
            lineGlow *= 0.08 + 0.20 * crust;
            lineAccum += lineGlow;
        }
    }

    // ----- Stray flakes: a sparse layer peeling off the boughs and drifting
    // DOWN with the wind (uv.y increases downward). Punctuation, not weather.
    float flakeAccum = 0.0;
    {
        vec2 q = uv * vec2(15.0, 10.0);
        q.x += wind * 1.2;                                  // ride the wind
        q.y += mod(iTime, 100.0) * 0.55;                    // fall DOWN
        vec2 cell = floor(q);
        float h = bxHash(cell);
        // GW_DENSITY lowers the keep-threshold to carry MORE stray flakes (lush)
        // or raises it for sparser 留白. density=1 leaves the authored ~7%.
        float fThresh = clamp(0.93 - (GW_DENSITY - 1.0) * 0.10, 0.05, 0.985);
        if (h > fThresh) {                                  // ~7% of cells at default
            vec2 f = fract(q);
            vec2 fc = vec2(fract(h * 17.3), fract(h * 31.7));
            f.x += sin(q.y * 0.5 + h * 6.28318) * 0.18;     // lateral wander
            float aspCell = aspect * (10.0 / 15.0);
            float fd = length((f - fc) * vec2(aspCell, 1.0));
            float tw = 0.5 + 0.5 * sin(mod(iTime, 100.0) * (0.7 + h * 1.5) + h * 6.28318);
            flakeAccum = smoothstep(0.05 * GW_GLOW, 0.0, fd) * tw * 0.45;  // GW_GLOW softens flakes
        }
    }

    // GW_DENSITY also scales how much the blossom field FILLS the frame: a
    // coverage multiplier over the blossom cores, halos and the crusted bough
    // line so >1 reads as a lusher, more laden bough and <1 thins it toward
    // bare branches. density=1 is identity (authored coverage).
    float densCov = GW_DENSITY;
    coreAccum *= densCov;
    haloAccum *= densCov;
    lineAccum *= densCov;

    // Compose. White blossom cores + blush halos + crust line + cool flakes.
    vec3 effect = coreCol * coreAccum
                + bloomCol * haloAccum
                + mix(bloomCol, coreCol, 0.5) * lineAccum
                + coreCol * flakeAccum;

    // A faint cool dawn lift hugging the very bottom edge (frontier sky
    // greying at the horizon). Tiny — never enters the text band.
    float dawn = smoothstep(0.0, 0.16, uv.y) * (1.0 - smoothstep(0.10, 0.22, uv.y));
    effect += vec3(0.10, 0.12, 0.20) * dawn * 0.11;

    effect = max(effect, 0.0);

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (blossom cores, blush
    // halos, bough glow and flakes alike) so the feeling reads at a glance —
    // cold/bleak (-1) through the authored silver (0) to warm/tender (+1).
    // Default 0 = identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;

    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
