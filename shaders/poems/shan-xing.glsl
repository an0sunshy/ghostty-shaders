// Shan Xing (山行 — Mountain Travel), Du Mu.
//   停車坐愛楓林晚，霜葉紅於二月花。
//   "I stop the cart, in love with the maple woods at dusk —
//    frosted leaves redder than spring blossoms."
//
// A sparse fall of crimson/ember MAPLE LEAVES — palmate, pointed, each on
// its own slender stem — tumbling diagonally from the top-right down to the
// bottom-left against a deep indigo dusk. Each leaf spins on its own axis and
// catches small gust jitter, so the descent is heavy and chaotic rather than
// the gentle drift of petals. The poem turns on a contrast — leaves "redder
// than spring blossoms" — so the silhouette is deliberately a sharp-lobed
// maple leaf, NOT a round five-petal flower.
//
// A faint warm ember glow hugs the bottom edge — the blazing maple wood the
// traveller has stopped to admire. The whole upper-center stays dark and open
// (留白) so terminal text reads cleanly; light lives only in the few tumbling
// leaves and the low horizon glow. The frame starts from black; nothing
// washes the background.
//
// Motion is driven entirely by iTime, wrapped through mod() so the fast
// rotation / sway terms never lose float precision at large iTime.
//
// Four "feeling" dials tune the scene from one shared control set (all-default
// reproduces the authored look exactly):
//   GW_MOOD    — global warm/cool tone over the whole frame (leaves + glow).
//   GW_ENERGY  — gust/flutter AGITATION of the falling leaves (not the rates),
//                so low = calm slow descent, high = chaotic windy tumble.
//   GW_DENSITY — how many leaves fall + how strong the wood glow (留白 vs lush).
//   GW_GLOW    — leaf-edge feather + glow softness and the wood-band bloom.

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

float sxHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 2D value noise + small fbm — gently perturbs the bottom maple-wood glow so
// it shimmers like distant foliage rather than sitting as a flat band.
float sxNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = sxHash(i);
    float b = sxHash(i + vec2(1.0, 0.0));
    float c = sxHash(i + vec2(0.0, 1.0));
    float d = sxHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float sxFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 3; i++) { v += a * sxNoise(p); p *= 2.07; a *= 0.5; }
    return v;
}

// Maple-leaf mask in local, de-rotated leaf space (roughly unit-scaled, leaf
// pointing +y). A real maple leaf is palmate: a handful of SHARP-cusped lobes
// radiating from a base, with a slender petiole (stem) trailing the opposite
// way. We build the silhouette from an angular radius profile:
//   - five lobes via abs(cos(2.5*a)) raised to a LOW power so the lobes stay
//     fat but plunge to deep cusps between them (the serrations of a maple),
//   - the whole leaf tapers toward its base (the stem end) so it is not
//     radially symmetric — it has a clear tip-up orientation,
//   - a thin petiole drawn as a separate narrow stripe below the blade.
// Returns soft 0..1 coverage with a feathered edge for a luminous, glyph-like
// read. No bright central pip — that is what made the old version look like a
// flower.
float mapleLeaf(vec2 lp) {
    float r = length(lp);
    float a = atan(lp.y, lp.x);

    // Slight vertical stretch so the silhouette is taller than wide — a leaf,
    // not a round rosette. Done in the radius calc by measuring against a
    // squashed coordinate.
    vec2 sp = vec2(lp.x * 1.18, lp.y * 0.92);
    float rs = length(sp);
    float as = atan(sp.y, sp.x);

    // Orient the leaf so a lobe points straight up (+y). Five SHARP lobes.
    // The deep contrast between lobe crown and cusp valley (pow 0.22) is what
    // makes the edge read as jagged maple serration instead of soft petals:
    // the crowns stay fat while the gaps between them plunge to thin cusps.
    float lobe = pow(abs(cos(as * 2.5 - 1.5707963 * 2.5)), 0.22);
    float radius = 0.20 + 0.70 * lobe;

    // Taper the lower half (the base, toward the petiole at -y) so the blade is
    // broad at the crown and narrows where the stem attaches — breaks the
    // radial symmetry a pure lobe field would have and gives a clear tip-up.
    float base = smoothstep(-1.0, 0.45, sp.y);   // 0 at bottom, 1 toward top
    radius *= mix(0.50, 1.0, base);

    // Feathered blade fill: solid toward the centre, soft falloff to the
    // jagged edge. Falloff kept narrow so coverage stays inside the cell and
    // the serrated outline survives. GW_GLOW widens the feather for a softer,
    // dreamier edge (or crisps it below 1); the silhouette radius is untouched
    // so the leaf keeps its size and only the edge bloom changes.
    float feather = 0.18 * GW_GLOW;
    float blade = smoothstep(radius, radius - feather, rs);

    // Slender petiole: a short narrow stripe trailing straight down from the
    // base, giving the leaf its characteristic stem tail.
    float stem = smoothstep(0.06, 0.0, abs(lp.x))           // thin in x
               * smoothstep(-1.0, -0.45, lp.y)              // only below base
               * smoothstep(-0.10, -0.45, lp.y);            // fade to the tip
    // Stem reads as a dim attachment, never brighter than the blade it hangs
    // from, so it looks like a petiole and not a light streak.
    return max(blade, stem * 0.55);
}

// One parallax layer of tumbling leaves on a cell grid. Diagonal drift
// (down + left), per-leaf rotation and gust sway, low occupancy so most cells
// are empty. Returns coverage in `cov` and the leaf's warm colour in `col`
// (palette blends maple-red -> ember-orange per leaf).
void leafLayer(vec2 uv, vec2 aspect, float scale, float fall, float density,
               float seed, out float cov, out vec3 col) {
    cov = 0.0;
    col = vec3(0.0);

    // Bounded time for the slow descent (continuous drift via mod is safe).
    float t = mod(iTime, 120.0);

    // Drift the SAMPLING grid. uv has top-origin (uv.y = 1 at the top). A leaf
    // appears where the sampled grid coordinate lands on it, so to make the
    // leaves travel a given way on screen the sampled grid must move the
    // OPPOSITE way. To send leaves toward the BOTTOM (decreasing uv.y) the
    // grid's y INCREASES with time; to send them toward the LEFT (decreasing
    // uv.x) the grid's x also INCREASES with time. The result is the poem's
    // top-right -> bottom-left tumble. Verified against rendered frames:
    // features descend and drift left as iTime grows.
    vec2 q = uv * scale + seed;
    q.y += t * fall;
    q.x += t * fall * 0.35;

    // GW_DENSITY scales the occupancy keep-fraction so more (>1, lush) or fewer
    // (<1, sparser 留白) cells carry a leaf. At 1.0 the authored density stands.
    float dens = clamp(density * GW_DENSITY, 0.0, 1.0);

    vec2 cell = floor(q);
    float h = sxHash(cell);
    if (h < 1.0 - dens) return;             // empty cell — cheapest path

    // Per-leaf in-cell anchor and traits. The anchor stays off the cell border
    // (0.32..0.68) and size + sway are bounded so a leaf's coverage never
    // reaches the cell edge — otherwise fract() would clip it into a hard
    // square. Each leaf therefore lives wholly inside its own cell.
    vec2 anchor = vec2(0.32 + 0.36 * fract(h * 17.3), 0.32 + 0.36 * fract(h * 31.7));
    float phase = h * 6.2831853;
    float spin  = mix(0.6, 1.5, fract(h * 53.1));   // rotation speed
    float size  = mix(0.34, 0.50, fract(h * 71.9)); // apparent leaf size

    // Gust sway: small chaotic horizontal flutter on top of the descent. tw is
    // a bounded fast oscillator (mod keeps the argument small).
    //
    // GW_ENERGY scales the flutter AMPLITUDE (calm <-> windy), NOT the oscillator
    // rates — scaling tw/spin would teleport leaves to new positions when the
    // dial is dragged. eAmp = 1.0 at default; an extra shared gust only grows
    // ABOVE default so the authored descent is left exactly as-is at 1.0.
    float eAmp = 0.45 + 0.55 * GW_ENERGY;                 // 1.0 at default
    float tw = mod(iTime, 60.0);
    vec2 f = fract(q) - anchor;
    f.x += sin(tw * (0.8 + spin) + phase) * 0.09 * eAmp;
    f.x += sin(mod(iTime, 47.0) * 0.6 + uv.y * 4.0 + phase) * 0.05 * max(GW_ENERGY - 1.0, 0.0);
    f.y += sin(tw * (0.5 + spin) * 0.7 + phase * 1.7) * 0.045 * eAmp;

    // Aspect-correct so leaves keep their shape, not stretched, on wide windows.
    vec2 lp = f * aspect / size;

    // Per-leaf rotation (the tumble): rotate lp by an angle advancing with
    // bounded time so leaves spin continuously as they fall.
    float ang = tw * spin + phase;
    float cs = cos(ang), sn = sin(ang);
    lp = mat2(cs, -sn, sn, cs) * lp;

    cov = mapleLeaf(lp);

    // Colour: blend maple-red -> ember-orange per leaf. A gentle radial
    // darkening toward the blade edge gives depth WITHOUT a bright flower-pip
    // centre — the leaf glows as a whole, not from a hot core.
    vec3 mapleRed = vec3(0.80, 0.23, 0.13);   // #cc3a21
    vec3 ember    = vec3(0.92, 0.63, 0.25);   // #eaa041
    col = mix(mapleRed, ember, fract(h * 91.3));
    col *= 0.78 + 0.22 * smoothstep(0.9, 0.2, length(lp));  // soft, even glow
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;

    // Terminal glyph layer sampled with the UNFLIPPED coordinate.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    vec2 aspect = vec2(iResolution.x / iResolution.y, 1.0);

    // --- Tumbling maple leaves: three parallax layers (far -> near). ---
    // Low densities keep the field sparse so the open centre stays dark.
    vec3 effect = vec3(0.0);

    float cov; vec3 lcol;
    leafLayer(uv, aspect, 6.5,  0.045, 0.05,  0.0,  cov, lcol);
    effect += lcol * cov * 0.55;                          // far / dim
    leafLayer(uv, aspect, 4.6,  0.065, 0.05,  13.7, cov, lcol);
    effect += lcol * cov * 0.80;                          // mid
    leafLayer(uv, aspect, 3.3,  0.090, 0.045, 27.3, cov, lcol);
    effect += lcol * cov * 1.05;                          // near / bright

    // --- Maple-wood glow along the bottom edge. ---
    // A warm gradient confined to the lowest band, shimmered by slow fbm so it
    // breathes like distant foliage catching the last dusk light. Strongest at
    // the very bottom, fading out well before mid-screen to preserve 留白.
    float t = mod(iTime, 90.0);
    // GW_GLOW widens the band's soft top edge for a dreamier bloom (or tightens
    // it below 1) while the bottom anchor stays put. GW_DENSITY scales the glow's
    // strength so a lusher scene carries a warmer wood and a sparser one recedes.
    float band = smoothstep(0.38 * GW_GLOW, 0.0, uv.y);   // bottom-weighted
    band *= band;                                          // tighten to the edge
    float shimmer = 0.62 + 0.42 * sxFbm(vec2(uv.x * 3.0, uv.y * 2.0 - t * 0.12));
    vec3 woodWarm = mix(vec3(0.66, 0.18, 0.10),           // deep maple crimson
                        vec3(0.90, 0.50, 0.20),           // ember orange
                        smoothstep(0.0, 0.28, uv.y));
    effect += woodWarm * band * shimmer * 0.30 * GW_DENSITY;

    // Mandatory additive composite — luminous-on-dark, text stays legible.
    effect = max(effect, 0.0);

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (leaves and the wood
    // glow alike) so the feeling reads at a glance — cold/bleak (-1) through the
    // authored dusk (0) to warm/tender (+1). Default 0 = identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;
    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}