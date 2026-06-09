// Clear Night — moon with realistic phase shape, plus a sparse twinkling
// starfield. Background-only; text passes through.
//
// Moon phase math:
//   MOON_PHASE ∈ [0,1)   0=new   0.25=first qtr   0.5=full   0.75=last qtr
//   The terminator (boundary between lit and dark) is an ellipse projected
//   from the moon's lit hemisphere. In local moon coords [-1, 1]:
//     phaseAngle = MOON_PHASE * 2π
//     ck = cos(phaseAngle)        // 1 at new, -1 at full
//     side = sign(sin(phaseAngle)) // +1 waxing, -1 waning
//     A point is LIT when:  side * lp.x  >=  ck * sqrt(1 - lp.y²)
//   This produces a sliver at new moon (only edge lit), full disk at full
//   moon, right hemisphere at first quarter, left hemisphere at last
//   quarter, and crescents in between. Verified against all four cardinal
//   phases.
//
// MOON_PHASE is baked at swap time by bin/ghostty-weather-swap from the
// current synodic cycle (~29.53d). Falls back to full if missing.

#ifndef MOON_PHASE
#define MOON_PHASE 0.5
#endif

float nightHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 2D value noise + 3-octave fbm for moon surface texture. Cheap enough
// to sample inside the disk mask without hurting framerate. Used to
// produce maria-like darker regions and a fine highland speckle.
float moonNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = nightHash(i);
    float b = nightHash(i + vec2(1.0, 0.0));
    float c = nightHash(i + vec2(0.0, 1.0));
    float d = nightHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float moonFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 3; i++) { v += a * moonNoise(p); p *= 2.1; a *= 0.5; }
    return v;
}

// Moon surface — limb darkening for the sphere illusion + procedural
// maria (low-frequency darker regions) + high-frequency highland speckle.
// Returns the surface color to use INSIDE the moon disk (lit portion).
//
// Color palette: warm cream highlands + neutral dark grey maria. The
// real moon is a slightly yellow-grey body, not the bluish silver that
// glow effects often default to. Overall brightness scaled down so the
// disk reads more "rocky body" than "luminous lamp".
vec3 moonSurface(vec2 lp) {
    // Limb darkening — lit hemisphere curves away from the observer.
    float limb = sqrt(max(0.0, 1.0 - dot(lp, lp)));
    float shade = mix(0.50, 0.92, limb);   // a touch dimmer overall
    // Maria: thresholded fbm produces a few large dark patches that look
    // like Imbrium / Tranquillitatis / Crisium without any texture lookup.
    // Lower threshold ramp → bigger / more visible mare regions.
    float maria = smoothstep(0.48, 0.70, moonFbm(lp * 2.3 + 11.0));
    // Two layers of highland variation — broader patchy texture + a
    // finer grain — for a more "rocky" surface.
    float patchy = moonFbm(lp * 4.5 + 7.1) * 0.15;
    float speck  = moonFbm(lp * 9.0 + 3.7) * 0.10;
    // Warm cream highlands, neutral grey maria.
    vec3 base = vec3(0.78, 0.75, 0.65);    // pale yellow-cream
    vec3 mare = vec3(0.38, 0.36, 0.34);    // neutral dark grey
    vec3 col = mix(base, mare, maria * 0.85) * shade;
    // Patchy/speck contribute desaturated brightness variations.
    col += vec3(patchy) - vec3(0.075);
    col += vec3(speck)  - vec3(0.05);
    return col;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;

    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // Moon position: upper area, slightly right of center. R + the inner
    // smoothstep edge below are chosen so the visible moon disk spans
    // aspect-corrected radius 0.034..0.040 — identical to the sun's disk
    // in clear-day.glsl. The two celestial bodies are now the same
    // on-screen size whatever the window aspect.
    vec2 moonPos = vec2(0.68, 0.74);
    float R = 0.040;
    vec2 aspect = vec2(iResolution.x / iResolution.y, 1.0);

    // Aspect-corrected local moon coords ∈ [-1, 1] at the disk edge.
    vec2 lp = (uv - moonPos) * aspect / R;
    float r = length(lp);

    // Phase shape calc
    float pa = MOON_PHASE * 6.2831853;
    float ck = cos(pa);
    float sideRaw = sin(pa);
    float side = sideRaw >= 0.0 ? 1.0 : -1.0;
    // Avoid the sign(0) ambiguity at exact new/full — fallback covers it.

    float termCurve = ck * sqrt(max(0.0, 1.0 - lp.y * lp.y));
    float isLit = step(termCurve, side * lp.x);

    // Smoothstep 1.0→0.85 in local moon coords gives a visible disk from
    // r*R = 0.034 (full bright) to r*R = 0.040 (fades out) — matches the
    // sun's smoothstep(0.040, 0.034, d) in clear-day.glsl exactly.
    float diskMask = smoothstep(1.0, 0.85, r);
    // Soften the terminator over a few percent of the disk so lit/dark
    // doesn't pixel-edge. The dark side now uses (1 - litMask) for the
    // earthshine contribution below.
    float litMask = smoothstep(-0.03, 0.03, side * lp.x - termCurve);
    float moonMask = diskMask * litMask;

    // Outer halo around the lit portion. The moon's *surface* now carries
    // its identity (limb darkening + maria + speckle), so the halo can be
    // calmer — 0.22 instead of 0.30. This also restores the sun-corona >
    // moon-halo hierarchy from earlier (sun corona is 0.20).
    //
    // Halo strictly outside the disk via smoothstep(0.95, 1.05, r) so it
    // never bleeds into the surface texture. Intensity scales with the
    // illuminated fraction (1 at full moon, 0 at new) rather than being
    // gated by `isLit` — that earlier directional gating produced a
    // one-sided glow that visibly flipped sides through the synodic
    // cycle. Symmetric ring + brightness proportional to phase looks
    // natural and never asymmetric.
    float litFrac = 0.5 * (1.0 - ck);  // ck=cos(pa): 1 at new, -1 at full
    float outerR = max(r - 1.0, 0.0);
    float halo = exp(-outerR * 9.0) * 0.22 * litFrac * smoothstep(0.95, 1.05, r);

    // Stars: sparse twinkle. Use a 15×10 grid; ~8% of cells fire a star.
    // Per-star color temperature: hot blue-whites (Vega) to warm orange
    // (Betelgeuse). Adds variety for one extra mix.
    float stars = 0.0;
    vec3 thisStarColor = vec3(0.70, 0.78, 0.90);  // default pale blue
    vec2 starGrid = uv * vec2(15.0, 10.0);
    vec2 starCell = floor(starGrid);
    vec2 starF = fract(starGrid);
    float starH = nightHash(starCell);
    if (starH > 0.92) {
        vec2 starP = vec2(fract(starH * 17.3), fract(starH * 31.7));
        float aspectCellRatio = (iResolution.x / iResolution.y) * (10.0 / 15.0);
        float starD = length((starF - starP) * vec2(aspectCellRatio, 1.0));
        float awayFromMoon = smoothstep(0.0, R * 1.5, distance(uv, moonPos));
        float twinkle = 0.55 + 0.45 * sin(mod(iTime, 100.0) * (0.6 + starH * 2.5) + starH * 6.28);
        stars = smoothstep(0.08, 0.0, starD) * twinkle * 0.55 * awayFromMoon;
        // Per-star color: cooler/warmer based on a second hash.
        float starTemp = fract(starH * 53.1);
        thisStarColor = mix(vec3(0.95, 0.80, 0.65),    // warm Betelgeuse
                            vec3(0.70, 0.78, 0.90),    // cool Vega
                            smoothstep(0.3, 0.8, starTemp));
    }

    // Moon surface shading replaces the uniform moonColor inside the
    // lit disk. Halo color matches the warmer body palette so the glow
    // isn't bluer than the disk it's surrounding.
    vec3 moonHaloColor = vec3(0.78, 0.75, 0.65);

    // PERF: moonSurface() runs three multi-octave fbm evaluations — the
    // dominant cost of this scene. It only contributes inside the disk
    // (moonMask and earthshine's darkMask are both gated by diskMask, which
    // is zero for r >= 1.0), yet the disk covers <1% of the screen. Compute
    // it only for fragments at or inside the disk edge; everywhere else the
    // surface terms are identically zero. This is visually lossless and cuts
    // the scene's cost ~20x (the moon disk is a tiny contiguous region, so
    // entire GPU warps outside it skip the fbm uniformly). See bench/.
    vec3 moonShaded = vec3(0.0);
    vec3 earthshine = vec3(0.0);
    if (r < 1.05) {
        moonShaded = moonSurface(lp);
        // Earthshine: the dark hemisphere catches faint reflected sunlight
        // from Earth, so it's never fully invisible. Strongest near new
        // moon (Earth nearly full from the moon's perspective), weakest near
        // full. Reads as "you can still see the whole moon outlined".
        float darkMask = diskMask * (1.0 - litMask);
        float earthshineStrength = mix(0.10, 0.03, litFrac);  // dim crescent → very dim full
        earthshine = moonShaded * earthshineStrength * darkMask;
    }

    vec3 effect = moonShaded * moonMask
                + earthshine
                + moonHaloColor * halo
                + thisStarColor * stars;

    vec3 bgFinal = iBackgroundColor + effect;
    vec3 outRgb = bgFinal * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
