// 錢塘湖春行 — Spring Stroll by Qiantang Lake (Bai Juyi)
//   "幾處早鶯爭暖樹，誰家新燕啄春泥。"
//   Early orioles vie for sun-warmed trees; whose new swallows peck at
//   spring mud?
//
// Early spring by West Lake: a calm, dark, luminous expanse of water; a
// low warm sun resting just off the horizon; and — the whole subject —
// new swallows darting and swooping low over the surface. The static
// world is held nearly silent (留白) so that quick, curved flight reads
// as the only motion. Three forked-tail swallow silhouettes trace fast
// quadratic-bezier swoop arcs across a wide dark field, dipping DOWN
// toward a single faint shimmer line low on screen (the lake) then
// climbing away again. The glyphs are drawn as clear swept-wing bird
// shapes — two raked wings sweeping back from a small body, with a short
// forked tail — so they read as birds, not abstract marks.
//
// Everything is additive luminous-on-dark; the center stays near-zero so
// terminal text passes through cleanly.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls. In THIS scene they drive:
//   * GW_MOOD    — global warm/cool tone over the whole lake (water, sun, birds)
//   * GW_ENERGY  — agitation of the swallows: wingbeat lift + a flight flutter
//                  (amplitudes only, never the swoop RATE — birds don't teleport)
//   * GW_DENSITY — how much the frame fills: bird brightness + water/ambient lift
//   * GW_GLOW    — bloom/softness: bird stroke widths, sun bloom, water band feather
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

// ---- hash / value-noise / fbm (inlined, self-contained) -------------------
float qhash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float qnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = qhash(i);
    float b = qhash(i + vec2(1.0, 0.0));
    float c = qhash(i + vec2(0.0, 1.0));
    float d = qhash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float qfbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * qnoise(p); p *= 2.07; a *= 0.5; }
    return v;
}

// Quadratic bezier between three control points.
vec2 bez2(vec2 a, vec2 b, vec2 c, float t) {
    float u = 1.0 - t;
    return u * u * a + 2.0 * u * t * b + t * t * c;
}

// Distance from point p to the line segment a-b (all in local space).
float segDist(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a;
    vec2 ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
    return length(pa - ba * h);
}

// One swallow rendered as a clear swept-wing bird silhouette, centered at
// p (aspect-corrected space), heading `dir` (unit), `s` = glyph size in
// aspect-space units, `flap` ∈ [0,1] raises/lowers the wing tips for a
// wingbeat. Returns an additive luminous mask built from a few soft line
// segments: a small body, two backswept wings each made of an inner and
// an outer raked stroke (the classic shallow-M of a bird in flight), and
// a short forked tail. Drawing along segments — rather than a radial
// blob — is what makes it read unmistakably as a bird.
float swallow(vec2 p, vec2 dir, float s, float flap) {
    // Local frame: x along flight (forward), y perpendicular (up = +y in
    // this local frame). The body points forward at +x.
    vec2 fwd  = dir;
    vec2 side = vec2(-dir.y, dir.x);
    vec2 q = vec2(dot(p, fwd), dot(p, side)) / s;

    // Wing tips lift slightly on the upbeat, drop on the downbeat.
    float lift = mix(0.55, 1.05, flap);

    // Key points of the silhouette in local glyph coords.
    // Body runs from a small head (front) to the tail root (back).
    vec2 head = vec2( 0.55, 0.0);
    vec2 tailRoot = vec2(-0.55, 0.0);
    // Shoulder where the wings join the body.
    vec2 shoulder = vec2(0.05, 0.0);
    // Each wing: an inner stroke out to a mid joint, then an outer stroke
    // raked back to the tip — gives the shallow-M / swept look. Wings are
    // swept slightly rearward (negative x at the tips) like a swallow.
    vec2 wingMidU = vec2(-0.10, 0.55 * lift);
    vec2 wingTipU = vec2(-0.65, 0.95 * lift);
    vec2 wingMidL = vec2(-0.10, -0.55 * lift);
    vec2 wingTipL = vec2(-0.65, -0.95 * lift);
    // Forked tail: two short prongs splaying back from the tail root.
    vec2 tailU = vec2(-1.00,  0.28);
    vec2 tailL = vec2(-1.00, -0.28);

    // Accumulate luminosity as a thin glow around each stroke; smaller
    // softness constant = crisper line. GW_GLOW widens the stroke softness so
    // birds bloom softer/dreamier above default, crisper below (1 = authored).
    float lum = 0.0;
    float w  = 0.0028 * GW_GLOW;   // body/wing stroke softness
    float wt = 0.0022 * GW_GLOW;   // tail stroke (a touch thinner)

    // Body.
    { float d = segDist(q, head, tailRoot); lum += 0.85 * w / (d * d + w); }
    // Upper wing (inner + outer).
    { float d = segDist(q, shoulder, wingMidU); lum += w / (d * d + w); }
    { float d = segDist(q, wingMidU, wingTipU); lum += w / (d * d + w); }
    // Lower wing (inner + outer).
    { float d = segDist(q, shoulder, wingMidL); lum += w / (d * d + w); }
    { float d = segDist(q, wingMidL, wingTipL); lum += w / (d * d + w); }
    // Forked tail.
    { float d = segDist(q, tailRoot, tailU); lum += 0.8 * wt / (d * d + wt); }
    { float d = segDist(q, tailRoot, tailL); lum += 0.8 * wt / (d * d + wt); }
    // Small bright head dot for a focal point.
    { vec2 hd = q - head; lum += 0.012 / (dot(hd, hd) + 0.010); }

    return lum;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                         // host is top-origin (uv.y=1 top)

    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    float aspect = iResolution.x / iResolution.y;
    // Aspect-corrected space: x widened by aspect so swoops & glyphs round.
    // After the flip above, larger uv.y sits toward the TOP of the screen
    // (uv.y=1 is the very top). So P.y = uv.y - 0.5 grows UPWARD: positive
    // P.y is high air, negative P.y is low toward the water/bottom.
    vec2 P = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);

    vec3 effect = vec3(0.0);

    // Palette
    vec3 birdCol  = vec3(0.596, 0.843, 0.894); // #98d7e4 luminous teal-white
    vec3 waterCol = vec3(0.35, 0.55, 0.70);    // cool lake glint
    vec3 sunCol   = vec3(1.00, 0.78, 0.46);    // low warm spring sun

    // ---- the lake: a single faint horizontal shimmer band LOW on screen ---
    // After the flip, larger uv.y is toward the TOP, so a LOW water line
    // needs a SMALL uv.y. Keep it dim and narrow so it reads as "water
    // surface", not a fill — most of the frame stays pure dark above it (留白).
    float horizon = 0.22;                      // low on screen (toward bottom)
    float bandY = uv.y - horizon;
    // Soft vertical falloff around the band. GW_GLOW widens the band's feather
    // (dividing the falloff rate by GW_GLOW^2 broadens the soft edge); 1 = authored.
    float band = exp(-bandY * bandY * 340.0 / (GW_GLOW * GW_GLOW));
    // Animated ripple texture along the band — slow continuous drift.
    float driftT = mod(iTime, 600.0);
    float ripple  = qfbm(vec2(uv.x * 9.0 - driftT * 0.20, uv.y * 22.0 + driftT * 0.10));
    float ripple2 = qfbm(vec2(uv.x * 18.0 + driftT * 0.35, uv.y * 30.0));
    // Sparse specular glints: gate the ripple field above a threshold so
    // highlights pop and vanish as the surface moves.
    float glint = smoothstep(0.66, 0.92, ripple) * smoothstep(0.55, 0.95, ripple2);
    // GW_DENSITY scales how much the lake fills the frame (留白 vs lusher water).
    float shimmer = band * (0.05 + 0.50 * glint) * GW_DENSITY;
    effect += waterCol * shimmer;

    // ---- low warm sun glow, resting just off the lower-right horizon ------
    // A soft, broad bloom — present but understated, lighting the water's
    // far edge. Positioned in aspect space near the low water line so it
    // sits on the horizon, not floating in the upper dark.
    vec2 sunPos = vec2(aspect * 0.30, -0.28);  // lower-right, on the horizon
    float sd = length(P - sunPos);
    // GW_GLOW broadens the sun's bloom radius (smaller falloff rate = wider glow);
    // 1 = authored.
    float sunGlow = exp(-sd * 5.5 / GW_GLOW) * 0.12;     // broad, gentle
    // A faint warm wash spilling along the horizon from the sun.
    float horizonWash = band * exp(-abs(P.x - sunPos.x) * 1.3 / GW_GLOW) * 0.09;
    effect += sunCol * (sunGlow + horizonWash);

    // ---- the swallows: fast curved swoop arcs (the whole subject) ---------
    // Each bird runs a quadratic bezier from an entry point in the air,
    // dipping DOWN toward the lake at the mid control point, to an exit
    // climbing away — looped on its own period and phase. P.y grows upward,
    // so "down toward the water" means the mid control has a SMALLER (more
    // negative) y than the entry/exit. Heading is the analytic bezier
    // tangent, so the glyph always faces its flight direction through the
    // dive and climb.
    const int NBIRDS = 3;
    for (int i = 0; i < NBIRDS; i++) {
        float fi = float(i);
        // Distinct flight per bird via a couple of hashes.
        float h0 = qhash(vec2(fi, 3.0));
        float h1 = qhash(vec2(fi, 9.0));
        float h2 = qhash(vec2(fi, 17.0));

        float period = 6.0 + 3.0 * h0;         // ~6-9s per swoop
        float phase  = h1;                     // 0..1 stagger
        float tt = fract(mod(iTime, period * 64.0) / period + phase);

        // Control points in aspect space. Birds cross the field on slightly
        // different lanes. P.y grows upward, so the lake (uv.y≈0.22) sits at
        // P.y≈-0.28; the mid control dips DOWN toward it for the swoop.
        float dir = (h2 < 0.5) ? 1.0 : -1.0;   // some fly L->R, some R->L
        float ax = -dir * aspect * 0.62;       // entry just off one edge
        float cx =  dir * (h0 - 0.5) * aspect * 0.30; // mid, near center-ish
        float bx =  dir * aspect * 0.62;       // exit off the other edge

        // y (upward-positive): start and end up in the air (small positive),
        // dip DOWN toward the water (negative y) at the mid control point.
        float ay =  0.18 - 0.12 * h0;          // enter up in the air
        float cyDip = -0.18 - 0.08 * h1;       // dip down toward the water
        float by =  0.16 - 0.14 * h2;          // climb back up into the air

        vec2 a = vec2(ax, ay);
        vec2 b = vec2(cx, cyDip);              // mid control = the dive point
        vec2 c = vec2(bx, by);

        vec2 pos = bez2(a, b, c, tt);
        // Analytic tangent of the quadratic bezier for heading.
        vec2 tang = 2.0 * (1.0 - tt) * (b - a) + 2.0 * tt * (c - b);
        float tl = max(length(tang), 1e-4);
        vec2 dirv = tang / tl;

        // GW_ENERGY scales motion AGITATION (wingbeat vigour + a flight flutter),
        // never the swoop RATE — so dialing it reads as calm<->lively flight, not
        // birds teleporting along the arc. Default (1.0) keeps the authored beat
        // and adds no flutter.
        float eAmp = 0.45 + 0.55 * GW_ENERGY;            // 1.0 at default
        float eExtra = max(GW_ENERGY - 1.0, 0.0);        // grows only above default

        // A gentle perpendicular flutter — a wind-buffet on the flight path that
        // sways the bird sideways to its heading. Wrap time for loop safety.
        vec2 sidev = vec2(-dirv.y, dirv.x);
        float flutter = sin(mod(iTime, 27.0) * (2.6 + 1.3 * h0) + fi * 1.7) * 0.012 * eExtra;
        pos += sidev * flutter;

        // Fade in/out at the ends of the arc so birds enter/leave gracefully.
        float edgeFade = smoothstep(0.0, 0.07, tt) * smoothstep(1.0, 0.93, tt);

        // Wingbeat: a 0..1 flap value pulsing the wing-tip lift, plus a
        // gentle brightness pulse. Wrap time for fast-oscillation safety.
        // GW_ENERGY scales the flap's SWING around its mid (0.5) via eAmp, so low
        // energy = a flatter, lazier wingbeat and high energy = a vigorous one,
        // without changing the beat RATE. Default leaves the authored swing.
        float beatPhase = mod(iTime, 100.0) * (9.0 + 4.0 * h1) + fi * 2.1;
        float flap = 0.5 + 0.5 * sin(beatPhase) * eAmp;
        float beat = 0.85 + 0.15 * sin(beatPhase);

        float glyph = swallow(P - pos, dirv, 0.058, flap);
        // GW_DENSITY scales the birds' presence (since the count is a fixed loop
        // bound, scale their luminous coverage instead) — fuller flock above 1,
        // sparser/fainter below. Default leaves the authored brightness.
        effect += birdCol * glyph * (0.038 * GW_DENSITY * edgeFade * beat);
    }

    // Faint cool ambient lift very low on screen only (the water's body),
    // tapering to pure dark above — preserves negative space for text.
    // Low on screen = small uv.y, so ramp up as uv.y -> 0. GW_DENSITY scales it
    // with the rest of the lake's fill so 留白 opens/closes coherently.
    float lowLift = smoothstep(0.22, 0.0, uv.y) * 0.022 * GW_DENSITY;
    effect += vec3(0.20, 0.32, 0.45) * lowLift;

    // Guard every channel >= 0.
    effect = max(effect, vec3(0.0));

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (water, sun, and the
    // swallows alike) so the feeling reads at a glance — cold/bleak (-1) through
    // the authored spring light (0) to warm/tender (+1). Default 0 = identity.
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;

    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}