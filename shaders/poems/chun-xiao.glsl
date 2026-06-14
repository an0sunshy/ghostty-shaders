// 春曉 (Chūn Xiǎo) — Spring Dawn — Meng Haoran
//   夜來風雨聲，花落知多少。
//   "Through the night, wind and rain — how many blossoms have fallen?"
//
// Pre-dawn dimness after a night storm. The wind and rain are already past;
// what remains is the quiet aftermath — a few last petals loosened from the
// branch, drifting down through still air, fading in at the top and out near
// the bottom. No people, no drama: just sparse, slow descent.
//
// We render that with:
//   * A small fixed set of soft petal blobs (7), each on its own slow
//     sinusoidal sway path, gently rotating, shaped as a rounded blossom
//     petal (wide cupped base tapering to a soft point), fading in near the
//     top and out near the bottom. Density is kept very low so petals occupy
//     well under 10% of the frame and the center stays open for text.
//   * A single small, warm pre-dawn blush dead-bottom-center — the day not
//     yet arrived, just a luminous hint that tapers hard to black on every
//     side. NOT a floor-wide band: it is a confined focal glow surrounded by
//     dark, so the frame keeps its 留白.
//
// Deliberately NO full-frame tint: the near-black charcoal IS the overcast
// pre-dawn sky. Light is sparse, warm, and focal; most of the frame stays at
// effect=0.
//
// Palette: warm petal-pink #f6c5be and pale cream #fef1d1 on charcoal #0a0a10.
// Additive, luminous-on-dark; most of the frame stays near-zero (留白).
//
// Four "feeling" dials (neutral defaults reproduce this authored look):
//   GW_MOOD    — global warm/cool tone over the whole scene.
//   GW_ENERGY  — petal sway AGITATION (amplitude + a gentle gust above 1), not rate.
//   GW_DENSITY — petal coverage + blush fill (lusher >1 / sparser 留白 <1).
//   GW_GLOW    — bloom/softness: petal size, core radius, and blush falloff.
//
// PERFORMANCE: the two heavy per-pixel costs — the multi-octave fbm that
// drives the blush, and the 7-petal loop (two cxPetal evaluations each) — are
// both gated behind cheap region tests. Almost the entire frame is empty
// charcoal: outside the small bottom-center glow the fbm is skipped, and a
// petal is evaluated only for pixels inside its tight bounding disc. Where the
// effect is zero those pixels still produce zero, so the gating is lossless.

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

// --- hash / value-noise / fbm (inlined, house style) -----------------------
float cxHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float cxHash1(float n) {
    return fract(sin(n * 91.3458) * 47453.5453);
}
float cxNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = cxHash(i);
    float b = cxHash(i + vec2(1.0, 0.0));
    float c = cxHash(i + vec2(0.0, 1.0));
    float d = cxHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float cxFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * cxNoise(p); p *= 2.03; a *= 0.5; }
    return v;
}

// A single soft blossom petal centered at the origin in aspect-corrected
// space. `q` is the fragment position relative to the petal center (already
// aspect-corrected); `rot` is the petal's rotation; `scale` its half-size.
// Returns a 0..1 coverage mask with a feathered edge.
//
// Shape: a rounded teardrop — wide and round at the base, narrowing to a
// soft point at the tip — with a shallow, symmetric cup so it reads as a
// flower petal rather than a crescent. We build it from a radial profile
// that is squashed along the petal's length and pinched toward the tip.
float cxPetal(vec2 q, float rot, float scale) {
    // Rotate into the petal's local frame.
    float cs = cos(rot);
    float sn = sin(rot);
    vec2 p = vec2(cs * q.x - sn * q.y, sn * q.x + cs * q.y);
    p /= max(scale, 1e-4);

    // p.y runs along the petal length (-1 base .. +1 tip). Normalize a
    // "height" coordinate h in [0,1] from base to tip.
    float h = clamp(0.5 + 0.5 * p.y, 0.0, 1.0);

    // Width profile: broad and rounded near the base (h~0.35), tapering
    // smoothly to a point at the tip (h=1) and rounding off at the very
    // base (h=0). sin(pi*h) gives a clean lobe; bias the fat part slightly
    // below center and sharpen the tip with a power.
    float lobe = sin(3.14159265 * clamp(h, 0.0, 1.0));
    float width = pow(lobe, 0.85) * 0.62;        // half-width at this height

    // Horizontal distance from the petal's midrib, normalized by the local
    // width. Inside the lobe -> <1; outside -> >1.
    float wEdge = abs(p.x) / max(width, 1e-3);

    // Feathered edge across the width, and a gentle fade at the extreme
    // base/tip so the silhouette is a soft closed blossom petal.
    float body  = smoothstep(1.15, 0.35, wEdge);
    float ends  = smoothstep(0.02, 0.14, h) * smoothstep(1.0, 0.86, h);
    return body * ends;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                       // host is top-origin: uv.y=1 top

    // Sample the terminal glyph layer with the UNFLIPPED coord.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    float aspect = iResolution.x / iResolution.y;

    vec3 effect = vec3(0.0);

    // ------------------------------------------------------------------
    // PRE-DAWN BLUSH — one small warm glow, dead-bottom-center. The day is
    // about to break but hasn't; this is a luminous hint, not a band. It
    // tapers hard to black on the sides (so it never becomes a floor-wide
    // wash) and stays low (under the bottom ~14% of cells). A slow fbm
    // drift makes it breathe. Float-safe: only a slow linear drift into
    // noise, no fast trig on raw iTime.
    //
    // The geometric falloff `blush` is exactly zero once `gd >= 0.62`, which
    // is true across the whole frame except the small bottom-center disc.
    // We compute that cheap falloff first and only sample the 4-octave fbm
    // when it is non-zero — almost every pixel skips the fbm entirely, and
    // the skipped pixels would have multiplied the fbm by zero anyway.
    // ------------------------------------------------------------------
    vec2 glowC = vec2(0.5, 0.0);                         // bottom-center anchor
    vec2 g = (uv - glowC) * vec2(aspect, 1.0);
    // Anisotropic falloff: a little wider than tall, but still compact.
    float gd = length(g * vec2(0.7, 1.9));
    // GW_GLOW widens the soft falloff radius so the blush reads dreamier (>1)
    // or crisper (<1); default 1.0 keeps the authored 0.62.
    float blushR = 0.62 * GW_GLOW;
    float blush = smoothstep(blushR, 0.0, gd);           // 1 at anchor -> 0 out
    if (blush > 0.0) {
        blush *= blush;                                  // tighten the core
        float blushN = cxFbm(vec2(uv.x * 2.4 + iTime * 0.012, 3.0));
        // GW_DENSITY scales the blush fill — a lusher (>1) or sparser (<1) glow.
        blush *= 0.16 * (0.62 + 0.6 * blushN) * GW_DENSITY;
        // Warm rosy blush easing to cream right at the bottom edge.
        vec3 blushCol = mix(vec3(0.98, 0.72, 0.63),      // rosy
                            vec3(1.00, 0.90, 0.74),      // warm cream core
                            smoothstep(0.14, 0.0, uv.y));
        effect += blushCol * blush;
    }

    // ------------------------------------------------------------------
    // FALLING PETALS — a small fixed set, each with its own slow descent,
    // sinusoidal sway, rotation, and fade in/out. Density is deliberately
    // tiny (7 petals, most small) so the frame stays open.
    //
    // Each petal i has:
    //   - a normalized fall progress t in [0,1) that loops via fract; the
    //     petal enters at the top (uv.y high) and exits at the bottom. Per-
    //     petal speed + phase offset stagger them so they never pulse in sync.
    //   - a base X column, plus a sinusoidal sway whose amplitude/phase are
    //     per-petal (gentle, residual drift — the storm is past).
    //   - rotation accumulating slowly as it tumbles.
    //   - fade: in near the top, out near the bottom, so petals appear/vanish
    //     softly instead of popping at the frame edge.
    //
    // FLOAT-SAFETY: fall progress uses fract(iTime * rate + phase) which is a
    // slow seamless loop; sway/rotation feed mod(iTime, P) into trig so a huge
    // iTime never blows up the oscillation.
    //
    // PERFORMANCE: each petal's coverage is non-zero only within a tight disc
    // around its center. cxPetal's body vanishes once the rotation-invariant
    // local distance leaves the lobe (|p.x| < ~0.71, |p.y| < 1), i.e. once
    // length(q) > scale * 1.25. We compute the petal's center/scale/fade with
    // only cheap scalar math, then skip both cxPetal evaluations (body + core)
    // for any pixel outside that disc or with fade == 0. The two smoothstep-
    // heavy shape calls then run for a handful of pixels per petal instead of
    // the whole frame; skipped pixels were contributing exactly zero.
    // ------------------------------------------------------------------
    const int PETALS = 7;
    for (int i = 0; i < PETALS; i++) {
        float fi = float(i);
        float h  = cxHash1(fi * 1.7 + 0.5);   // primary per-petal random
        float h2 = cxHash1(fi * 3.1 + 2.3);   // secondary random
        float h3 = cxHash1(fi * 5.9 + 7.1);   // tertiary random

        // Fall: slow, residual. Each petal takes ~20-38s to cross the screen.
        float period = mix(20.0, 38.0, h);
        float rate   = 1.0 / period;
        float t = fract(iTime * rate + h);    // 0 at top, ->1 at bottom

        // Fade: in over the first 12% of the fall, out over the last 18%.
        float fadeIn  = smoothstep(0.0, 0.12, t);
        float fadeOut = smoothstep(1.0, 0.82, t);
        float fade = fadeIn * fadeOut;

        // Off-screen / fully-faded petals contribute nothing — skip the whole
        // shape evaluation before touching the sway/rotation trig.
        if (fade <= 0.0) continue;

        // Vertical position: start a little above the top (1.08) so the
        // fade-in happens off-screen, end a little below the bottom (-0.08).
        float y = mix(1.08, -0.08, t);

        // Base column, spread across the width but biased away from dead
        // center so the busiest text rows stay clearer.
        float baseX = 0.10 + 0.80 * h2;

        // Sway: a gentle horizontal oscillation that also grows slightly as
        // the petal descends (air settling). Two wrapped sines at different
        // rates give an irregular, un-mechanical drift.
        //
        // GW_ENERGY scales AGITATION (sway AMPLITUDE + a shared lateral gust),
        // NOT the oscillator rate — so dialing it reads as still<->lively air
        // rather than teleporting petals to new columns. Default (1.0) keeps the
        // authored sway and adds no gust.
        float eAmp = 0.45 + 0.55 * GW_ENERGY;                          // 1.0 at default
        float swA = (0.045 + 0.05 * h3) * eAmp;
        float sw1 = sin(mod(iTime, 31.0) * (0.45 + 0.5 * h) + h * 6.2831853);
        float sw2 = sin(mod(iTime, 19.0) * (0.9 + 0.6 * h2) + h2 * 6.2831853);
        float sway = (sw1 * 0.7 + sw2 * 0.3) * swA * (0.5 + 0.7 * t);
        // Extra gust that grows ONLY above default — a shared breath of wind
        // that nudges every petal together when energy is high.
        float gust = sin(mod(iTime, 23.0) * 0.6 + y * 4.0) * 0.05 * max(GW_ENERGY - 1.0, 0.0);
        float x = baseX + sway + gust;

        // Size: most petals small, a couple slightly larger for depth.
        // GW_GLOW grows the petal's soft footprint so blossoms read softer /
        // dreamier (>1) or crisper (<1). Scaling `scale` here also widens the
        // bounding disc below, so the feathered edge is never clipped.
        float scale = mix(0.030, 0.052, h3) * GW_GLOW;

        // Position relative to petal center, aspect-corrected so the petal
        // keeps its shape regardless of window aspect.
        vec2 q = (uv - vec2(x, y)) * vec2(aspect, 1.0);

        // Cheap bounding-disc reject: cxPetal's coverage is contained within
        // local |p|<~1.25, and rotation preserves length, so any pixel with
        // length(q) > scale*1.25 has zero body AND zero core. Use squared
        // distance to avoid the sqrt. Tiny margin so the feathered edge is
        // never clipped.
        float bound = scale * 1.3;
        if (dot(q, q) > bound * bound) continue;

        // Rotation: slow tumble. Accumulate via a wrapped time term plus a
        // per-petal base angle; the sway also nudges the angle so the petal
        // appears to bank as it drifts.
        float rot = h * 6.2831853
                  + sin(mod(iTime, 27.0) * (0.35 + 0.4 * h2) + fi) * 0.8
                  + sway * 4.0;

        float mask = cxPetal(q, rot, scale) * fade;

        // Color: warm petal-pink core easing to pale cream at the bright
        // center, with a faint per-petal warmth variation. Brightness modest
        // so petals read as luminous-soft, not blown-out.
        vec3 pink  = vec3(0.96, 0.77, 0.72);   // #f6c5be petal-pink
        vec3 cream = vec3(1.00, 0.94, 0.82);   // #fef1d1 pale cream
        // Bias toward pink so petals read as blossom, not white flecks;
        // a minority lean cream for variety.
        vec3 petalCol = mix(pink, cream, h2 * 0.45);

        // Add a small brighter warm core inside the soft body so each petal
        // has a luminous heart, kept light so the pink body stays dominant.
        float core = cxPetal(q, rot, scale * 0.55);
        vec3 coreCol = mix(petalCol, cream, 0.5);
        // GW_DENSITY scales each petal's coverage/alpha so the frame fills in
        // lusher (>1) or thins toward 留白 (<1) without changing the petal
        // COUNT (keeping the loop bound fixed); default 1.0 = authored.
        effect += petalCol * mask * 0.60 * GW_DENSITY;
        effect += coreCol  * core * fade * 0.22 * GW_DENSITY;
    }

    // ------------------------------------------------------------------
    // Composite (mandatory): additive, luminous-on-dark; text legible.
    // ------------------------------------------------------------------
    effect = max(effect, 0.0);

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (petals and blush
    // alike) so the feeling reads at a glance — cool/overcast (-1) through the
    // authored warm pink (0) to warm/tender (+1). Default 0 = identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;

    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
