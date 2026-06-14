// 靜夜思 (Jìng Yè Sī) — Quiet Night Thoughts — Li Bai
//   床前明月光，疑是地上霜。
//   "Before my bed, bright moonlight — I take it for frost on the ground."
//
// A small, contained glimpse of a cold night sky: a soft luminous moon sits
// low-left, partly veiled by a thin band of cloud that drifts slowly across
// its face. The light it casts is pale and cold enough to be mistaken for
// frost. A few silver frost-glints twinkle faintly in the moon's near glow.
//
// Maximal 留白: the moon + its veil occupy only a modest region; the whole
// upper screen, the center, and the right two-thirds stay near-black so
// terminal text reads cleanly. Start from pure black and add only luminous
// focal light — no full-frame sky wash.
//
// Four "feeling" dials (neutral at the defaults — all-default = authored look):
//   GW_MOOD    global warm/cool tint over the whole scene
//   GW_ENERGY  motion AGITATION — moon-breath / cloud-drift / twinkle amplitude
//   GW_DENSITY fill vs 留白 — cloud coverage + how many frost glints survive
//   GW_GLOW    bloom/softness — moon disk+halo radii, veil feather, glint size

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

float jnHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 2D value noise + 4-octave fbm for the cloud veil and the moon's feathered
// halo, so edges dissolve into soft grain rather than clean shapes.
float jnNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = jnHash(i);
    float b = jnHash(i + vec2(1.0, 0.0));
    float c = jnHash(i + vec2(0.0, 1.0));
    float d = jnHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float jnFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * jnNoise(p); p *= 2.03; a *= 0.5; }
    return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                       // host top-origin: uv.y=1 top

    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    float aspect = iResolution.x / iResolution.y;

    // --- Slow drift cycles (float-safe: wrap iTime before any sin) ---------
    // Multi-minute loops so motion is "almost imperceptible" — only the cloud
    // veil slides perceptibly over the moon; the moon itself barely breathes.
    float tA = mod(iTime, 240.0) / 240.0 * 6.2831853;   // 4-min cycle
    float tB = mod(iTime, 168.0) / 168.0 * 6.2831853;   // 2.8-min cycle

    // GW_ENERGY scales motion AGITATION (drift / sway / twinkle AMPLITUDE),
    // never the oscillator RATES — so dialing it reads as calm<->lively air
    // rather than teleporting the moon/veil to new positions. eAmp = 1.0 at the
    // default; the extra `gust` term grows ONLY above default.
    float eAmp = 0.45 + 0.55 * GW_ENERGY;          // 1.0 at default
    float eExtra = max(GW_ENERGY - 1.0, 0.0);      // 0 at/below default

    // The moon sits low-left, a small contained focal point. Aspect-correct
    // space so the disk and its glow are round, not stretched by the window.
    vec2 moonPos = vec2(0.34, 0.62);
    moonPos.x += 0.010 * sin(tA) * eAmp;     // imperceptible breathing drift
    moonPos.y += 0.008 * sin(tB) * eAmp;
    vec2 q = (uv - moonPos);
    q.x *= aspect;
    float r = length(q);

    // --- Cloud veil ---------------------------------------------------------
    // A thin horizontal band of cloud drifts RIGHTWARD across the moon's face
    // over the long cycle. It both glows where the moon backlights it and
    // occludes the moon where it is thick — this veiling is the heart of the
    // 意境 (light softened, cold, frost-like). The veil is spatially confined
    // to the moon's neighbourhood so it never becomes a full-frame wash.
    vec2 cUV = vec2(uv.x * aspect, uv.y) * vec2(2.3, 5.5);
    cUV.x -= 0.18 * sin(tA) * eAmp;          // slow horizontal drift (energy = amplitude)
    cUV.y += 0.05 * sin(tB) * eAmp;
    // A gentle extra lateral gust that only appears above default energy, so
    // high energy reads as a livelier night air ruffling the veil.
    cUV.x -= 0.10 * sin(mod(iTime, 47.0) * 0.27 + uv.y * 2.5) * eExtra;
    float cloudN = jnFbm(cUV + 4.0);
    // Band membership: clouds live in a shallow horizontal strip near the moon
    // height, fading out vertically and with distance from the moon so the
    // rest of the frame stays clean dark.
    float bandY  = exp(-pow((uv.y - moonPos.y) * 6.5, 2.0));   // shallow strip
    float nearMoon = smoothstep(0.55, 0.10, r);                // confined region
    // GW_DENSITY scales how much the veil FILLS vs leaves 留白: drop the
    // coverage threshold for a lusher, thicker veil; raise it for a sparer,
    // wispier one. density=1 keeps the authored 0.45..0.85 ramp.
    float cloLo = 0.45 - (GW_DENSITY - 1.0) * 0.18;
    float cloud = smoothstep(cloLo, 0.85, cloudN) * bandY * nearMoon;

    // --- Moon disk + feathered cold halo -----------------------------------
    // Small soft disk. No hard rim — the moon is a luminous cold body seen
    // through air, so its edge feathers out via fbm into the surrounding glow.
    float haloN = jnFbm(vec2(uv.x * aspect, uv.y) * 5.0
                        + vec2(0.04 * sin(tA), -0.03 * sin(tB)));
    // GW_GLOW scales the bloom RADII and soft-edge widths so >1 reads dreamier
    // (a wider, softer corona and fuzzier rim) and <1 crisper. glow=1 keeps the
    // authored radii exactly.
    float rF = r + (haloN - 0.5) * 0.05 * GW_GLOW;   // feather the glow rim
    float disk = smoothstep(0.085 * GW_GLOW, 0.020, rF);          // bright core
    float halo = smoothstep(0.40 * GW_GLOW, 0.060, rF) * 0.45;    // soft cold corona

    // The drifting cloud DIMS the moon's core where it passes in front of it,
    // and the cloud itself lights up (backlit). occl ∈ [~0.45, 1]: never
    // fully blacks the moon out, just veils it.
    float occl = 1.0 - 0.55 * cloud;
    disk *= occl;

    // --- Sparse frost glints in the cold glow ------------------------------
    // ~a handful of tiny additive silver points on a coarse grid, each
    // twinkling on a per-cell phase-offset sine, gated to fire only within the
    // moon's near glow (where the cold light "settles as frost").
    float glints = 0.0;
    vec2 gGrid = vec2(uv.x * aspect, uv.y) * 11.0;
    vec2 gCell = floor(gGrid);
    vec2 gF    = fract(gGrid);
    float gH   = jnHash(gCell);
    // GW_DENSITY scales how many cells host a frost glint: lower the keep-gate
    // for a luscher dusting of frost, raise it for a sparser one. density=1
    // keeps the authored ~30% (gate 0.70).
    float gGate = clamp(0.70 - (GW_DENSITY - 1.0) * 0.18, 0.05, 0.97);
    if (gH > gGate) {
        vec2 gP = vec2(fract(gH * 17.3), fract(gH * 31.7));
        float gD = length(gF - gP);
        // GW_ENERGY scales the twinkle AMPLITUDE (depth of the in/out fade),
        // not its rate: low energy = steadier glints, high energy = livelier.
        float twAmp = clamp(0.5 * eAmp, 0.0, 0.5);   // 0.5 at default
        float tw = (0.5 - twAmp) + (2.0 * twAmp) * (0.5 + 0.5 * sin(
                       mod(iTime, 90.0) * (0.5 + gH * 1.6) + gH * 6.2831853));
        tw = tw * tw;                        // sharpen the in/out fade
        glints = smoothstep(0.080 * GW_GLOW, 0.0, gD) * tw;   // GW_GLOW: softer glints
    }
    // Glints only live in the moon's cold glow, and dim under thick cloud.
    glints *= smoothstep(0.40, 0.08, r) * (1.0 - 0.5 * cloud);

    // --- Compose luminous contribution -------------------------------------
    vec3 moonFill  = vec3(0.81, 0.88, 1.00);  // cold moonlight  #cfe0ff-ish
    vec3 cloudGlow = vec3(0.55, 0.62, 0.78);  // dim grey-blue backlit veil
    vec3 frostGlow = vec3(0.91, 0.94, 1.00);  // faint silver    #e8f0ff

    vec3 effect = moonFill  * disk  * 0.95
                + moonFill  * halo  * 0.40
                + cloudGlow * cloud * 0.30
                + frostGlow * glints * 0.80;

    effect = max(effect, 0.0);

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (moon, veil, and the
    // frost glints alike) so the feeling reads at a glance — cold/bleak (-1)
    // through the authored cold moonlight (0) to warm/tender (+1). Default 0 =
    // identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;

    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}