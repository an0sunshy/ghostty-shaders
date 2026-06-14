// 早發白帝城 (Zǎo Fā Báidìchéng) — Leaving Baidi at Dawn — 李白 (Li Bai), Tang
//   兩岸猿聲啼不住，輕舟已過萬重山。
//   "From both banks the gibbons' cries never cease —
//    yet the light boat has already slipped past ten thousand mountains."
//
// Pure velocity. A tiny skiff barely moves on screen while the dawn gorge
// rushes past it. The scene composites, from back to front:
//   - a faint dawn-violet glow low on the horizon at the far end of the gorge
//     (the dawn the boat is sailing out of), and a whisper of paling sky,
//   - two stacks of luminous gorge-RIDGE silhouettes hugging the LEFT and
//     RIGHT margins. Each ridge edge is rim-lit by dawn; the stacks SCROLL
//     DOWNWARD-AND-OUTWARD at parallax speeds (near ridges fast, far ridges
//     slow) so the viewer reads as racing FORWARD through the gorge,
//   - a few thin pale-cyan river speed-streaks low and central, rushing
//     DOWNWARD fast past the boat — the water tearing by,
//   - one small warm-amber boat point holding near center, swaying 2-3px.
// The center vertical channel stays dark dawn-sky so terminal text reads
// cleanly (留白); all light hugs the two margins, the low horizon, and the
// single boat. The MOTION is the receding mountains, not the boat.
//
// Direction check: glsl_image renders upright. iTime increasing pushes ridge
// rows and river streaks toward the BOTTOM of the frame (and ridges outward
// to the margins) — exactly the "world streaming backward as you race
// forward downstream" read the poem wants. Verified across t=1,5,9.
//
// Palette: dawn-violet sky #1a1530, slate gorge walls #0c1018 (rim-lit warm),
//          amber boat #ffbc6b, pale river streaks #aecbe0.
//
// Cost: the rim/river/dawn effects all hug the margins + low waterline; the
// wide dark center channel contributes ~0. Each heavy block is gated behind a
// cheap region test (rim per-side at xin<0.30, river/dawn at uv.y<0.48) so the
// noise-heavy gorge sampling and the streak loop never run for the many empty
// center/upper pixels. The gates are placed exactly at each effect's existing
// hard cutoff, so the rendered image is unchanged.
//
// Dials (GW_MOOD / GW_ENERGY / GW_DENSITY / GW_GLOW, defined below): a global
// warm/cool tint, the boat-sway / river-shimmer / dawn-breath agitation, the
// rim+streak+dawn coverage, and the bloom radii respectively. All-default
// (0,1,1,1) is the exact authored scene above.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls.
//   GW_MOOD    global warm/cool tone over the whole gorge (cold dawn .. warm sun)
//   GW_ENERGY  agitation of the boat sway/bob, river shimmer, and dawn breath
//              (amplitudes only — never the scroll/parallax rate, so the
//              receding mountains keep their authored pace and never teleport)
//   GW_DENSITY coverage of the rims, river streaks, dawn band and reflection
//   GW_GLOW    bloom: rim widths, river-streak/boat halo radii, dawn softness
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

// --- hash / value-noise (house style; inlined, defined before use) ---

float zbHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float zbNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = zbHash(i);
    float b = zbHash(i + vec2(1.0, 0.0));
    float c = zbHash(i + vec2(0.0, 1.0));
    float d = zbHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Soft round point glow in aspect-corrected space. Returns 0..1.
float zbGlow(vec2 p, vec2 c, float r) {
    float d = length(p - c);
    return exp(-d * d / max(r * r, 1e-4));
}

// One parallax gorge wall hugging a margin. `side` = -1 (left) or +1 (right).
// The rock body fills the OUTER margin (toward x=0 on the left, x=1 on the
// right) up to a jagged ridge line; a thin luminous dawn-rim runs along that
// ridge crest. The ridge is kept firmly in the outer band of the frame so the
// center channel stays dark for text (留白). `speed` sets parallax: nearer
// walls (big speed) crag more and their crags travel DOWN faster. `seed`
// decorrelates layers/sides. Outputs the rim glow; returns nothing else.
//
// The ridge x-profile is value-noise sampled in a frame that translates
// DOWNWARD as `scroll` grows, so successive crags sweep toward the bottom —
// the forward-rush parallax. `xin` (distance inward from this wall's margin)
// is computed once by the caller and passed in, since it is layer-independent.
float gorgeRim(float xin, float uvy, float speed, float seed, float scroll) {
    // Downward-scrolling sample frame; larger speed => faster travel.
    float row = uvy + scroll * speed;
    float n = zbNoise(vec2(seed, row * 5.0));
    n = 0.6 * n + 0.4 * zbNoise(vec2(seed + 4.0, row * 11.0));

    // Ridge sits in the OUTER band only. baseReach is small; jag adds crag.
    // Even the nearest (fastest) layer's crest stays well outside x=0.5: max
    // ridge ≈ baseReach + jagAmp = 0.10 + 0.12 = 0.22 from the margin.
    float baseReach = 0.06 + 0.04 * speed;        // 0.06 .. ~0.12
    float jagAmp    = 0.06 + 0.06 * speed;         // 0.06 .. ~0.12
    float ridge = baseReach + jagAmp * n;          // inward distance of crest

    // Thin luminous rim hugging the crest. Distance from fragment to crest in
    // the inward axis; the band is narrow so it reads as a lit rock edge, not
    // a fill. Nearer walls get a slightly wider, brighter rim. GW_GLOW widens
    // the rim's soft falloff so the crests bloom into a dreamier dawn haze.
    float dRim = xin - ridge;                      // <0 outside (toward margin)
    float w = (0.012 + 0.010 * speed) * GW_GLOW;
    float rim = exp(-dRim * dRim / max(w * w, 1e-4));

    // Hard cut anything past the center band so a stray crag can never reach
    // the text channel; rim fully gone by xin = 0.30. (The gate stays fixed at
    // 0.30 independent of the dials so the per-side skip remains exact.)
    rim *= smoothstep(0.30, 0.18, xin);

    // Vertical crag streaking so the rim shimmers as rock streams past.
    float streak = 0.7 + 0.3 * zbNoise(vec2(seed + xin * 10.0, row * 22.0));
    return rim * streak;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                 // host is top-origin: uv.y = 1 at top

    // Sample the terminal glyph layer with the UNFLIPPED coord.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    float aspect = iResolution.x / iResolution.y;
    vec2 ap = vec2(uv.x * aspect, uv.y);   // aspected position for round glows

    // Seamless looping clocks. Never feed raw iTime to fast oscillators.
    // The scroll is a monotone fract ramp (float-safe) that the walls read in
    // their own scaled frames; it wraps cleanly so the gorge never jumps.
    float scroll = fract(iTime * (1.0 / 30.0)) * 4.0;   // downward parallax ramp
    float tStream = mod(iTime, 12.0);                   // river streak phase

    vec3 effect = vec3(0.0);

    // ---- dawn at the far end of the gorge : a low violet/amber horizon glow ----
    // The boat is racing OUT of dawn; a soft paling band sits low-center where
    // the gorge opens. Kept dim and low so the text-center stays dark. The band
    // fades to 0 by |uv.y - 0.30| = 0.26, i.e. above uv.y = 0.56 — gate it so
    // the upper frame skips this block entirely (it contributes nothing there).
    if (uv.y < 0.57) {
        float horizon = 0.30;
        // GW_GLOW widens the dawn band's soft falloff (dreamier paling sky).
        float band = smoothstep(0.26 * GW_GLOW, 0.0, abs(uv.y - horizon));
        // Concentrate the dawn toward the open center channel, fading at edges.
        float centerBias = smoothstep(0.0, 0.45, 0.5 - abs(uv.x - 0.5)) ;
        // GW_ENERGY scales only the breath AMPLITUDE (the ±0.20 swing), not its
        // rate — dial low = a still dawn, high = a pulsing one. Default keeps
        // the authored 0.80 ± 0.20.
        float bAmp = 0.45 + 0.55 * GW_ENERGY;                  // 1.0 at default
        float breath = 0.80 + 0.20 * bAmp * sin(mod(iTime, 37.0) * 0.17);
        vec3 dawnCol = vec3(0.32, 0.22, 0.40);   // dawn-violet, faintly warm
        // GW_DENSITY scales the dawn's fill (lusher glow vs sparser 留白).
        effect += dawnCol * band * centerBias * breath * 0.22 * GW_DENSITY;
        // A thinner warm amber sliver right at the waterline = first sun.
        float sliver = smoothstep(0.05 * GW_GLOW, 0.0, abs(uv.y - (horizon - 0.02)));
        effect += vec3(0.55, 0.34, 0.16) * sliver * centerBias * 0.30 * GW_DENSITY;
    }

    // ---- 萬重山 : two parallax gorge-ridge stacks hugging the margins ----
    // Three layers per side at parallax speeds (far/slow .. near/fast) give the
    // racing-forward read. Each layer's luminous rim is dawn-tinted; warmer and
    // brighter for nearer (faster) layers, cooler/dimmer for far ones, so depth
    // is legible. Loop bound constant for portability.
    //
    // Every layer's rim is hard-cut to 0 by xin = 0.30 (the smoothstep in
    // gorgeRim). `xin` is layer-independent, so compute it once per side and,
    // when this wall's rim cannot reach the fragment (xin >= 0.30 — the entire
    // dark center channel), skip the whole 3-layer noise loop for that side.
    // This is the dominant cost and is exactly lossless: skipped pixels were
    // already receiving 0 from every layer.
    const int LAYERS = 3;
    for (int s = 0; s < 2; s++) {
        float side = (s == 0) ? -1.0 : 1.0;
        // Inward coordinate: 0 at this wall's margin, growing toward center.
        float xin = (side < 0.0) ? uv.x : (1.0 - uv.x);
        if (xin >= 0.30) continue;               // outside this wall's rim band
        for (int L = 0; L < LAYERS; L++) {
            float fl = float(L);
            // Far layer (L=0) slow; near layer (L=2) fast. Distinct speeds make
            // the parallax legible: the near rim visibly outruns the far one.
            float speed = 0.40 + 0.50 * fl;          // 0.40 .. 1.40
            float seed  = 13.0 * fl + 47.0 * float(s) + 3.0;
            float rim   = gorgeRim(xin, uv.y, speed, seed, scroll);
            // Depth shading: near ridges warmer + brighter, far cooler + dimmer.
            float depth = fl / float(LAYERS - 1);     // 0 far .. 1 near
            vec3 rimCol = mix(vec3(0.34, 0.28, 0.46),  // far: cool dawn-violet
                              vec3(0.98, 0.68, 0.34),  // near: warm dawn-amber
                              depth);
            float bright = mix(0.30, 0.70, depth);
            // Rim fades toward the very top and bottom edges so layers feel like
            // crags streaming through, not full-height bars.
            float vfade = smoothstep(0.0, 0.10, uv.y) * smoothstep(1.0, 0.88, uv.y);
            // GW_DENSITY scales how lush the gorge walls read (more/less rim).
            effect += rimCol * rim * bright * vfade * GW_DENSITY;
        }
    }

    // ---- river : thin pale-cyan speed-streaks rushing DOWNWARD past the boat ----
    // Horizontal streaks low and central, scrolling fast toward the bottom to
    // read as water tearing by. A few discrete bands (constant count) keep them
    // legible rather than a smear. Confined to the lower-center water plane.
    //
    // Every streak lives at yPos in 0.02..0.32 with a very thin band
    // (exp(-yd^2/4.5e-5) is <1e-6 beyond |yd|~0.024), and the waterline wash
    // fades to 0 by uv.y = 0.46. Gate the whole block to the lower frame so the
    // upper-frame pixels skip the streak loop entirely — they get 0 from it.
    if (uv.y < 0.48) {
        const int NSTREAK = 5;
        float waterTop = 0.42;                       // streaks live below this
        for (int k = 0; k < NSTREAK; k++) {
            float fk = float(k);
            // Each streak has its own base height + speed; they recycle from the
            // waterline downward as the fast scroll ramps (float-safe fract).
            float spd = 0.55 + 0.30 * zbHash(vec2(fk, 2.0));
            float y0  = 0.10 + 0.30 * fract(zbHash(vec2(fk, 7.0)) + tStream * spd * (1.0/12.0));
            // Travel downward: subtract the scrolling phase from uv.y target.
            float yPos = waterTop - y0;              // somewhere in 0.0..0.32
            float yd = abs(uv.y - yPos);
            // GW_GLOW widens each streak's gaussian (softer, dreamier water).
            float bw = 0.000045 * GW_GLOW * GW_GLOW;
            float band = exp(-yd * yd / max(bw, 1e-9)); // very thin horizontal line
            // Horizontal extent: brightest near center, tapering before margins
            // (so it doesn't fight the gorge walls).
            float xspan = smoothstep(0.5, 0.16, abs(uv.x - 0.5));
            // Streaks brighten/dim as they fall (motion shimmer). GW_ENERGY
            // scales only the shimmer AMPLITUDE (the ±0.35 swing), not its rate,
            // so the water reads calmer/livelier without the streaks jumping.
            float sAmp = 0.45 + 0.55 * GW_ENERGY;     // 1.0 at default
            float shimmer = 0.5 + 0.5 * sin(mod(iTime, 9.0) * (6.0 + fk) + fk * 2.4 + uv.x * 30.0);
            vec3 streakCol = vec3(0.68, 0.80, 0.88);  // pale river #aecbe0
            effect += streakCol * band * xspan * (0.30 + 0.35 * sAmp * shimmer) * 0.55 * GW_DENSITY;
        }
        // A faint cool wash exactly on the waterline anchors the river plane.
        float surf = smoothstep(0.04 * GW_GLOW, 0.0, abs(uv.y - waterTop));
        float xspanS = smoothstep(0.5, 0.18, abs(uv.x - 0.5));
        effect += vec3(0.34, 0.46, 0.56) * surf * xspanS * 0.10 * GW_DENSITY;
    }

    // ---- 輕舟 : one small warm-amber boat holding near center, swaying ----
    // The boat barely moves — a tiny lateral sway + a gentle bob — while the
    // world streams past. It sits just above the waterline in the open center.
    {
        float boatBaseX = 0.500;
        float boatBaseY = 0.470;                     // just above waterTop=0.42
        // 2-3px sway/bob at 520px wide ≈ 0.005 in uv. Two slow incommensurate
        // sines so it never looks mechanical; wrapped mod for float-safety.
        // GW_ENERGY scales only the sway/bob AMPLITUDES (not their rates), so a
        // low dial = the skiff nearly still, a high dial = it rocks harder —
        // the boat never teleports. Default (1.0) keeps the authored 2-3px.
        float eAmp = 0.45 + 0.55 * GW_ENERGY;        // 1.0 at default
        float sway = (0.006 * sin(mod(iTime, 19.0) * 0.83)
                   +  0.003 * sin(mod(iTime, 7.0) * 1.7)) * eAmp;
        float bob  = 0.004 * sin(mod(iTime, 11.0) * 1.1 + 0.7) * eAmp;
        vec2 boatC = vec2((boatBaseX + sway) * aspect, boatBaseY + bob);
        // Warm amber lamp: tight core + soft halo. Small so it reads as distant.
        // GW_GLOW widens the core+halo radii so the lamp blooms when dreamy.
        float core = zbGlow(ap, boatC, 0.013 * GW_GLOW);
        float halo = zbGlow(ap, boatC, 0.045 * GW_GLOW) * 0.45;
        // Subtle lantern flicker so the skiff feels alive.
        float fl = 0.85 + 0.15 * sin(mod(iTime, 5.0) * 4.3 + 1.2);
        vec3 boatCore = vec3(1.00, 0.82, 0.52);
        vec3 boatGlow = vec3(1.00, 0.74, 0.42);      // amber boat #ffbc6b-ish
        effect += (boatCore * core + boatGlow * halo) * fl * 1.10;
        // Short wavering reflection just under the boat on the water.
        float depth = boatBaseY - uv.y;
        if (depth > 0.0 && depth < 0.16) {
            float wob = 0.012 * sin(mod(iTime, 13.0) * 2.0 + uv.y * 40.0) * eAmp;
            float colX = (boatBaseX + sway) * aspect + wob;
            float dx = abs(ap.x - colX);
            float w = (0.010 + 0.05 * depth) * GW_GLOW;
            float streak = exp(-(dx * dx) / max(w * w, 1e-4));
            float vfall = exp(-depth * 16.0);
            effect += vec3(0.95, 0.66, 0.36) * streak * vfall * fl * 0.55;
        }
    }

    // ---- MANDATORY composite : additive, luminous-on-dark, text legible ----
    effect = max(effect, vec3(0.0));

    // GW_MOOD: a global warm/cool tone over the WHOLE gorge (dawn glow, ridge
    // rims, river streaks, and the boat alike) so the feeling reads at a glance —
    // cold/bleak (-1) through the authored dawn-violet (0) to warm sunrise (+1).
    // Default 0 = identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;
    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
