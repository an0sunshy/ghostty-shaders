// 暮江吟 (Mù Jiāng Yín) — Song of the River at Dusk — 白居易 (Bái Jūyì), Tang
//   一道殘陽鋪水中，半江瑟瑟半江紅。
//   "A last shaft of setting sun spreads across the water;
//    half the river is jade-cold, half blazing red."
//
// A broad river at sundown. From back to front the scene composites:
//   - a dim dusk-sky gradient hugging only the TOP edge (kept empty/dark in
//     the center so terminal text reads cleanly — 留白),
//   - a low, dull setting-sun disc near the horizon that eases DOWNWARD over a
//     long loop (殘陽, the sun sinking) and reddens as it falls,
//   - the river surface across the LOWER half, split tonally into two halves
//     meeting at a soft, shimmering vertical seam mid-frame: a blazing
//     amber-red half where the light strikes (半江紅) and a cold jade-teal
//     half lying in shadow (半江瑟瑟); the seam breathes left/right with the
//     water,
//   - a bright horizontal RIBBON of sun-glints laid flat across the water
//     (一道殘陽鋪水中) — a travelling, flickering field of specular highlights,
//     densest on the warm half and at the sun's column, animated by a scrolling
//     ripple field; the ribbon slowly lowers and reddens as the sun sinks.
// Most of the upper-center frame stays near-black so glyphs read cleanly.
//
// Palette: blazing amber-red #e8662c (lit half), deep jade-teal #1e4a44
//          (the 瑟瑟 shadowed half), dark muted dusk sky above.
//
// Four "feeling" dials (neutral at default, so all-default = authored look):
//   GW_MOOD    global warm/cool tone over the whole scene;
//   GW_ENERGY  ripple/seam/glint AGITATION amplitude (calm <-> lively water);
//   GW_DENSITY how lush the surface tone + glint ribbon fill vs 留白;
//   GW_GLOW    bloom/softness of the sun disc, halo, ribbon and glints.

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

// --- hash / value-noise / fbm (house style; inlined, defined before use) ---

float mjHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float mjNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = mjHash(i);
    float b = mjHash(i + vec2(1.0, 0.0));
    float c = mjHash(i + vec2(0.0, 1.0));
    float d = mjHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float mjFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * mjNoise(p); p *= 2.05; a *= 0.5; }
    return v;
}

// Soft round glow in aspect-corrected space. Returns 0..1.
float mjGlow(vec2 p, vec2 c, float r) {
    float d = length(p - c);
    return exp(-d * d / max(r * r, 1e-4));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                 // host is top-origin: uv.y = 1 at top

    // Sample the terminal glyph layer with the UNFLIPPED coord.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // Aspect-correct so the glint shapes and sun stay round on any window.
    float aspect = iResolution.x / iResolution.y;
    vec2 ap = vec2(uv.x * aspect, uv.y);

    // Seamless looping clocks. Never feed raw iTime to fast oscillators.
    float tSlow  = mod(iTime, 600.0);   // very slow: sun set + reddening
    float tWave  = mod(iTime, 90.0);    // medium: seam breathing
    float tRip   = mod(iTime, 60.0);    // fast: ripple scroll / glint flicker

    // Horizon where sky meets water. The river occupies everything below.
    float horizon = 0.46;

    // Sun sinks DOWNWARD across the slow loop: from just above the horizon
    // toward (and a touch below) it. cos-based so the loop is seamless. As it
    // sinks, `sunset` -> 1 and the whole scene reddens / dims.
    float sunset = 0.5 - 0.5 * cos(tSlow * (6.2831853 / 600.0)); // 0..1, smooth
    float sunY   = mix(horizon + 0.085, horizon - 0.010, sunset); // sinks down
    float sunX   = 0.50;                       // sun column centered horizontally
    vec2  sunC   = vec2(sunX * aspect, sunY);

    vec3 effect = vec3(0.0);

    // ---- dim dusk sky : ONLY a faint gradient hugging the very TOP edge ----
    // Concentrated above uv.y ~ 0.80 and feathered out before reaching the
    // text center, so the middle of the frame stays ~0. Warms toward the
    // sun's horizontal column. Reddens as the sun sinks.
    {
        float topBand = smoothstep(0.80, 1.0, uv.y);   // 0 below 0.80, 1 at top
        // A gentle warm lift right over the sun's column near the horizon line,
        // simulating the afterglow — but very dim and narrow.
        vec3 skyHi  = mix(vec3(0.20, 0.13, 0.20), vec3(0.34, 0.16, 0.12), sunset);
        effect += skyHi * topBand * 0.13;
    }

    // ---- 殘陽 : the low setting sun disc near the horizon, sinking ----
    // A dull, hazy disc — not a bright lamp — that reddens and dims as it sets.
    {
        // GW_GLOW softens/sharpens the sun by scaling its glow RADII (the r in
        // exp(-d*d/(r*r))). >1 = a hazier, dreamier disc + wider halo; <1 = a
        // crisper sun. Default 1.0 = authored radii.
        float disc = mjGlow(ap, sunC, 0.040 * GW_GLOW);
        disc = smoothstep(0.20, 1.0, disc);
        float halo = mjGlow(ap, sunC, 0.17 * GW_GLOW) * 0.40;
        // Color: amber when high, deep blood-red when low.
        vec3 sunCol = mix(vec3(1.00, 0.66, 0.30), vec3(0.91, 0.30, 0.16), sunset);
        // Dims as it sinks (atmospheric extinction at the horizon).
        float sunDim = mix(1.0, 0.55, sunset);
        effect += sunCol * (disc * 0.52 + halo * 0.30) * sunDim;
    }

    // ---- river ripple field (drives the glint ribbon + seam shimmer) ----
    // Directional scrolling fbm. Travels so glints continuously break apart and
    // re-form across the surface. Stronger near the foreground (lower uv.y).
    float ripScroll = fract(tRip * (1.0 / 60.0)) * 4.0;
    float rip1 = mjFbm(vec2(uv.x * 7.0,  uv.y * 18.0 - ripScroll));
    float rip2 = mjFbm(vec2(uv.x * 3.5 + 7.0, uv.y * 11.0 + ripScroll * 0.6));
    float ripple = rip1 * 0.65 + rip2 * 0.35;

    // GW_ENERGY scales the AGITATION of the water — the AMPLITUDE of the ripple
    // field's deviation about its ~0.5 mean (and, below, the seam's breathing
    // swing), NOT the scroll/oscillator RATE. Scaling rate would teleport the
    // glints; scaling amplitude reads as calm <-> choppy. `eAmp` = 1.0 at the
    // default so the authored ripple is untouched; above default a faint extra
    // chop grows in. We expand the deviation around 0.5 and re-clamp to [0,1].
    float eAmp = 0.45 + 0.55 * GW_ENERGY;                          // 1.0 at default
    float eChop = sin(mod(iTime, 47.0) * 0.9 + (uv.x + uv.y) * 9.0)
                * 0.06 * max(GW_ENERGY - 1.0, 0.0);                // 0 at/below default
    ripple = clamp(0.5 + (ripple - 0.5) * eAmp + eChop, 0.0, 1.0);

    // ---- river surface : two-tone split (半江瑟瑟半江紅) ----
    // Everything below the horizon. The seam between warm and cool halves sits
    // mid-frame and breathes left/right with the water. The warm half lies on
    // the sun's side; the cool jade half on the other.
    float water = smoothstep(0.0, 0.04, horizon - uv.y);   // 0 above horizon
    if (water > 0.0) {
        // Depth into the river (0 at horizon, grows toward the foreground).
        float depth = clamp((horizon - uv.y) / horizon, 0.0, 1.0);

        // Breathing vertical seam. Centered near mid-frame, wobbling with a slow
        // wave plus a per-row ripple so the boundary "shimmers and shifts".
        float seam = 0.5
                   + 0.045 * eAmp * sin(tWave * (6.2831853 / 90.0))
                   + 0.05 * (ripple - 0.5);
        // Soft transition warm<->cool across the seam (a few % of frame wide).
        float warmSide = smoothstep(seam - 0.07, seam + 0.07, uv.x);
        // The lit (warm) half is on the LEFT here so the lit band leads from the
        // sun's reflected column; flip so warm = the side the light strikes.
        warmSide = 1.0 - warmSide;   // 1 on warm/left, 0 on cool/right

        // Base tones, both kept fairly dim so the surface reads as dusk water
        // rather than a glowing wash — brightness lives in the glint ribbon.
        vec3 warmCol = mix(vec3(0.34, 0.11, 0.05), vec3(0.44, 0.14, 0.06), sunset);
        vec3 coolCol = vec3(0.04, 0.18, 0.16);     // jade-teal #1e4a44 (瑟瑟)
        vec3 baseWater = mix(coolCol, warmCol, warmSide);
        // Fade the surface tone toward the dark foreground so the very bottom
        // doesn't form a solid colour wash — keeps it luminous-on-dark.
        float surfFade = mix(0.9, 0.28, depth);
        // GW_DENSITY: how lushly the surface tone + glint ribbon fill the lower
        // half vs leaving it dark/open (留白). Scales the additive strengths so
        // >1 reads as a richer, more covered river and <1 thins it toward bare
        // water. Default 1.0 leaves the authored amounts.
        effect += baseWater * water * surfFade * 0.42 * GW_DENSITY;

        // ---- 一道殘陽鋪水中 : the horizontal sun-glint ribbon ----
        // The single shaft of setting sun "spread across the water": a broad
        // luminous swath laid flat just below the sun, brightest along the
        // sun's column and biased to the warm half, dissolving into discrete
        // travelling glints via the ripple field. The whole ribbon lowers and
        // reddens with sunset.
        float ribbonY = mix(horizon - 0.045, horizon - 0.14, sunset); // lowers
        // A wide soft band (the spread shaft) + a brighter near-horizon core.
        // GW_GLOW widens/narrows the shaft's soft falloff: these use the
        // exp(-dy*dy*K) form where the soft-edge radius ~ 1/sqrt(K), so divide
        // the K's by GW_GLOW^2 to scale the feather width by GW_GLOW. Default
        // 1.0 = authored widths.
        float invGlow2 = 1.0 / max(GW_GLOW * GW_GLOW, 1e-4);
        float dyA = uv.y - ribbonY;
        float dyB = uv.y - (ribbonY - 0.11);
        float ribbonBand = exp(-dyA * dyA * 95.0 * invGlow2)
                         + 0.55 * exp(-dyB * dyB * 22.0 * invGlow2);
        // Concentrate the glints under the sun's column horizontally — a smooth
        // tongue of light leading down from the disc.
        float colDist = abs(uv.x - sunX);
        float colMask = exp(-colDist * colDist * 6.0);
        // The continuous lit-shaft base (legible ribbon, not just sparkles).
        float shaft = ribbonBand * colMask;
        // Sharpen ripple into discrete travelling glint sparkles riding it.
        float sparkle = smoothstep(0.60, 0.90, ripple);
        // Finer high-frequency twinkle, sampled with bilinear value-noise (not
        // raw hash) so it stays smooth, not blocky, at low resolutions.
        float fine = smoothstep(0.55, 1.0,
                       mjNoise(vec2(uv.x * 26.0, uv.y * 34.0 - ripScroll * 2.0)));
        float glint = (shaft * 0.55                       // continuous shaft
                     + (sparkle * 0.7 + fine * 0.45)       // travelling glints
                       * ribbonBand * (0.30 + 0.70 * colMask));
        // Glints far stronger on the warm half (the lit side), faint on jade.
        glint *= mix(0.18, 1.0, warmSide);
        // Glint colour reddens as the sun sets.
        vec3 glintCol = mix(vec3(1.00, 0.74, 0.36), vec3(0.97, 0.41, 0.20), sunset);
        effect += glintCol * glint * water * 1.05 * GW_DENSITY;

        // A soft cool jade shimmer on the shadowed half so it isn't dead — the
        // 瑟瑟 (rustling jade) catching a little stray skylight.
        float jadeShim = smoothstep(0.5, 1.0,
                            mjNoise(vec2(uv.x * 18.0, uv.y * 30.0 + ripScroll)));
        jadeShim *= (1.0 - warmSide) * water * smoothstep(horizon, horizon - 0.18, uv.y);
        effect += vec3(0.10, 0.30, 0.27) * jadeShim * 0.16 * GW_DENSITY;
    }

    // ---- MANDATORY composite : additive, luminous-on-dark, text legible ----
    effect = max(effect, vec3(0.0));

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (sky, sun, water,
    // and glints alike) so the feeling reads at a glance — cold/jade-leaning
    // (-1) through the authored dusk balance (0) to warm/blazing (+1). Default
    // 0 = identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;
    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}