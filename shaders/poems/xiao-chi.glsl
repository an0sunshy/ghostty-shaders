// 小池 (Xiǎo Chí) — Small Pond — 楊萬里 (Yáng Wànlǐ), Song
//   小荷才露尖尖角，早有蜻蜓立上頭。
//   "The young lotus has just thrust up its sharp little tip —
//    and already a dragonfly has perched upon its head."
//
// A still, near-black pond. Almost the whole frame is calm dark water (留白),
// so terminal text stays legible. Light is concentrated in a single delicate
// focal cluster, low and right of center:
//   - a thin pale-jade lotus-bud SPIKE rising from the water to a sharp tip,
//   - faint expanding concentric RING-RIPPLES where the stem meets the water,
//   - a single slender DRAGONFLY that HOVERS and darts in small quick jittered
//     steps, then eases DOWN to rest on the bud's tip — its two wing-pairs
//     fast-flickering as iridescent translucent quads.
// The dragonfly's hover-and-settle is the obvious thing-in-motion; everything
// else (ripples, a whisper of surface shimmer) is slow and quiet.
//
// Palette: iridescent cyan-green dragonfly #42d692, pale jade lotus tip
//          #a0eac9, glassy black-blue water #04120f.
//
// Four "feeling" dials tune the scene (defaults reproduce the authored look
// exactly): GW_MOOD warms/cools the whole palette; GW_ENERGY scales the
// dragonfly's hover/dart/tremor AMPLITUDE (calm<->lively, not its rate);
// GW_DENSITY scales pond shimmer + ripple fill (留白<->lush); GW_GLOW scales
// every bloom radius and soft edge (crisp<->dreamy).

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

// --- hash / value-noise (house style; inlined, defined before use) ---

float xcHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float xcNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = xcHash(i);
    float b = xcHash(i + vec2(1.0, 0.0));
    float c = xcHash(i + vec2(0.0, 1.0));
    float d = xcHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Soft round point glow in aspect-corrected space. Returns 0..1.
float xcGlow(vec2 p, vec2 c, float r) {
    float d = length(p - c);
    return exp(-d * d / max(r * r, 1e-4));
}

// Signed distance to a segment a->b, for drawing the thin stem/spike and the
// dragonfly's slender body.
float xcSegDist(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a;
    vec2 ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
    return length(pa - ba * h);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                 // host is top-origin: uv.y = 1 at top

    // Sample the terminal glyph layer with the UNFLIPPED coord.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // Aspect-correct so circular glows / distances stay true on any window.
    float aspect = iResolution.x / iResolution.y;
    vec2 ap = vec2(uv.x * aspect, uv.y);

    // Seamless looping clocks. Never feed raw iTime to fast oscillators.
    float tRip  = mod(iTime, 90.0);    // slow ripple birth cycle
    float tFly  = mod(iTime, 12.0);    // dragonfly dart cycle (one hop loop)
    float tWing = mod(iTime, 0.6);     // very fast wing flicker

    // GW_ENERGY scales motion AMPLITUDE (how far the dragonfly wanders / how
    // hard it tremors), never the oscillator RATES above — so the dial reads as
    // calm<->lively rather than teleporting the bug to new positions. eAmp=1.0
    // at default; eGust adds a faint extra hover drift only ABOVE default.
    float eAmp  = 0.45 + 0.55 * GW_ENERGY;       // 1.0 at default
    float eGust = max(GW_ENERGY - 1.0, 0.0);     // 0.0 at/below default

    vec3 effect = vec3(0.0);

    // Focal geometry. The lotus bud sits low and to the right of center so the
    // text center stays dark and clear. waterY is the pond surface height at
    // the stem; the spike rises ABOVE it to a sharp tip.
    float stemX  = 0.635;                       // off-center to the right
    float waterY = 0.34;                        // surface line (low on screen)
    vec2  baseW  = vec2(stemX * aspect, waterY); // where stem meets water
    float tipY   = 0.58;                         // sharp little tip height
    vec2  tipP   = vec2(stemX * aspect, tipY);   // the bud tip in aspect space

    // ---- glassy pond : a whisper of cold shimmer ONLY low on screen ----
    // No full-frame wash. A faint horizontal shimmer band hugs the water line
    // and fades to nothing above it, so the upper 2/3 stays ~black for text.
    {
        float waterMask = smoothstep(0.46, 0.0, uv.y); // only lower screen
        // Slow drifting micro-glints on the mirror surface.
        float gl1 = xcNoise(vec2(uv.x * 22.0, uv.y * 40.0 - tRip * 0.15));
        float gl2 = xcNoise(vec2(uv.x * 9.0 + 4.0, uv.y * 16.0 + tRip * 0.08));
        float shimmer = smoothstep(0.72, 1.0, gl1) * 0.6
                      + smoothstep(0.80, 1.0, gl2) * 0.4;
        // Cold glassy black-blue tint #04120f lifted just barely above bg.
        // GW_DENSITY scales how much surface shimmer fills the water (留白<->lush).
        vec3 waterCol = vec3(0.18, 0.40, 0.36);
        effect += waterCol * shimmer * waterMask * 0.05 * GW_DENSITY;
    }

    // ---- 漣漪 : expanding concentric ring-ripples at the stem foot ----
    // A few rings born at staggered phases spread OUTWARD from baseW, growing
    // in radius and fading as they widen — like the disturbance of the stem on
    // the still mirror. Confined near the water line so they don't wash up.
    {
        const int NRINGS = 3;
        float rd = length(ap - baseW);
        for (int i = 0; i < NRINGS; i++) {
            float fi = float(i);
            // Each ring's age cycles through [0,1); offset per-ring phase.
            float age = fract(tRip * (1.0 / 9.0) + fi * 0.333);
            float radius = 0.012 + age * 0.16;       // grow outward
            float fade = (1.0 - age);                // dim as it widens
            fade = fade * fade;
            // Thin bright ring at `radius`; thickness grows slightly with age.
            // GW_GLOW softens the ring (wider, dreamier band) vs crisper at <1.
            float thick = (0.006 + age * 0.012) * GW_GLOW;
            float ring = exp(-pow(rd - radius, 2.0) / max(thick * thick, 1e-4));
            // Rings live just on/under the surface: suppress well above water.
            float surf = smoothstep(0.10, -0.02, uv.y - waterY);
            vec3 rippleCol = vec3(0.30, 0.62, 0.50); // jade-tinted glint
            // GW_DENSITY scales ripple presence (the count is a fixed loop bound,
            // so we fill via alpha to keep default-1 identical).
            effect += rippleCol * ring * fade * surf * 0.16 * GW_DENSITY;
        }
    }

    // ---- 小荷 : the thin lotus-bud spike rising to a sharp tip ----
    // A slim tapered stem from the water line up to tipP, capped by a small
    // pointed pale-jade bud. Drawn with a segment SDF; width tapers toward the
    // tip so it reads as "尖尖角" (a sharp little horn).
    {
        float d = xcSegDist(ap, baseW, tipP);
        // Height fraction 0 at water, 1 at tip — taper the stroke toward 1.
        float hfrac = clamp((uv.y - waterY) / max(tipY - waterY, 1e-4), 0.0, 1.0);
        float halfW = mix(0.010, 0.0015, hfrac);     // tapers to a point
        float stem = smoothstep(halfW, 0.0, d);
        // Only above the water line.
        stem *= smoothstep(-0.01, 0.02, uv.y - waterY);
        // Pale jade #a0eac9, brighter toward the tip (the bud catches light).
        vec3 jade = mix(vec3(0.34, 0.62, 0.46), vec3(0.63, 0.92, 0.79), hfrac);
        effect += jade * stem * 0.9;

        // The bud tip: a small soft jade glow crowning the spike, so the
        // dragonfly clearly has a "head" to perch on. GW_GLOW widens the halo.
        float bud = xcGlow(ap, tipP, 0.020 * GW_GLOW);
        effect += vec3(0.63, 0.92, 0.79) * bud * 0.45;
    }

    // ---- 蜻蜓 : a single dragonfly that hovers, darts, then settles ----
    // Motion model: most of the dart cycle is small quick jitter ABOVE/around
    // the tip (hovering), then over the final stretch it eases DOWN to rest on
    // the bud tip. A new dart begins each tFly loop. settle∈[0,1] = how landed.
    {
        // Eased landing: 0 while hovering, ramps to 1 (perched) at cycle end,
        // with a brief takeoff back up at the very start of the next loop.
        float c = tFly * (1.0 / 12.0);               // 0..1 over the loop
        float settle = smoothstep(0.45, 0.92, c);    // descends to perch
        settle *= smoothstep(0.0, 0.06, c);          // quick takeoff at loop top

        // Hover home: just above and slightly left of the tip when airborne.
        vec2 hover = tipP + vec2(-0.035, 0.075);
        // Quick jittered darting — small fast steps via stepped noise so it
        // snaps between nearby points rather than gliding. The jitter shrinks
        // as it settles (a perched dragonfly is still; only the wings move).
        // GW_ENERGY scales the dart AMPLITUDE (eAmp) — wider wander when lively,
        // tighter hover when calm — without touching the stepped dart RATE.
        float step1 = floor(tFly * 6.0);             // ~6 darts/loop, stepped
        vec2 jit = vec2(xcNoise(vec2(step1, 1.3)) - 0.5,
                        xcNoise(vec2(step1, 7.1)) - 0.5) * 0.085 * eAmp;
        // Fine fast tremor on top of the stepped darts (amplitude scaled too).
        float trem = sin(tFly * 9.0) * 0.006 * eAmp;
        // Extra slow hover drift that grows ONLY above default (a livelier breeze).
        vec2 gust = vec2(sin(mod(iTime, 7.0) * 0.9), cos(mod(iTime, 11.0) * 0.7))
                    * 0.02 * eGust;
        // Airborne position: hovering home + darting jitter + tremor + gust.
        vec2 air = hover + jit + vec2(trem, trem * 0.6) + gust;
        // Perch point: body resting just atop the bud tip.
        vec2 perch = tipP + vec2(0.0, 0.018);
        // Body eases from the airborne (jittering) point DOWN to the perch as
        // `settle` ramps 0->1 over the dart cycle, then takes off again.
        vec2 body = mix(air, perch, settle);

        // --- slender body (thorax->abdomen), tilted slightly head-down on perch
        float tilt = mix(0.55, 0.95, settle);        // more upright when landed
        vec2 bodyDir = normalize(vec2(0.18, -1.0) * tilt + vec2(0.0, -0.02));
        vec2 tail = body - bodyDir * 0.072;          // long thin abdomen
        vec2 head = body + bodyDir * 0.013;          // small head toward tip
        float db = xcSegDist(ap, head, tail);
        // Abdomen tapers toward the tail like a real dragonfly.
        float bh = clamp(dot(ap - head, tail - head)
                         / max(dot(tail - head, tail - head), 1e-4), 0.0, 1.0);
        float bodyHalf = mix(0.0050, 0.0022, bh);
        float bodyStroke = smoothstep(bodyHalf, 0.0, db);
        // Iridescent cyan-green body #42d692, head a touch brighter.
        effect += vec3(0.26, 0.84, 0.52) * bodyStroke * 0.8;
        effect += vec3(0.55, 0.95, 0.70) * xcGlow(ap, head, 0.010 * GW_GLOW) * 0.5;

        // --- two wing pairs: fast-flickering translucent membranes ---
        // A dragonfly's four long narrow wings sweep nearly horizontal. Each
        // wing is an elongated translucent blade: a segment SDF gives the long
        // axis, and an anisotropic falloff (tight across, loose along) makes a
        // slender leaf-shaped membrane rather than a round dot. The fast beat
        // modulates both their tilt and opacity so they blur like real wings.
        float beat = 0.5 + 0.5 * sin(tWing * (6.2831853 / 0.18)); // fast beat
        // Wings spread wide and roughly level; fold/tilt slightly when perched.
        float spread = mix(1.0, 0.82, settle);
        // Wing anchor at the thorax (just behind the head).
        vec2 wa = body + bodyDir * 0.002;
        vec2 perp = vec2(-bodyDir.y, bodyDir.x);  // across-body axis
        // Four wings: fore-L, fore-R, hind-L, hind-R (constant unrolled set).
        for (int w = 0; w < 4; w++) {
            float fw = float(w);
            float sideSign = (mod(fw, 2.0) < 0.5) ? 1.0 : -1.0; // L/R
            float isHind = (fw < 2.0) ? 0.0 : 1.0;
            // Hind pair anchors a little behind the fore pair along the body.
            vec2 wroot = wa - bodyDir * (0.014 * isHind);
            // Long axis: mostly across the body, swept slightly toward the
            // tail, with the beat lifting/dropping the outer tip (flap).
            float flap = (beat - 0.5) * 0.012 * sideSign;
            vec2 wlong = perp * sideSign + bodyDir * (-0.45 + 0.10 * isHind);
            wlong = normalize(wlong);
            float wlen = (0.052 + 0.006 * beat) * spread;
            vec2 wtip = wroot + wlong * wlen + bodyDir * flap;
            // Anisotropic membrane: distance to the wing's long axis, but
            // measured tightly across so the blade stays narrow. GW_GLOW softens
            // the membrane edge (the falloff is an r^2 term, so scale by GW_GLOW^2).
            float dw = xcSegDist(ap, wroot, wtip);
            float wing = exp(-dw * dw / (0.000045 * GW_GLOW * GW_GLOW));
            // Translucent, beating opacity; fore wings a touch brighter.
            float wingOpacity = (0.16 + 0.30 * beat) * mix(1.0, 0.82, isHind);
            // Iridescent cyan -> green shimmer across the beat.
            vec3 wingCol = mix(vec3(0.30, 0.85, 0.80), vec3(0.46, 0.92, 0.54),
                               beat);
            effect += wingCol * wing * wingOpacity;
        }

        // Faint motion blur halo while airborne (reads as a hovering shimmer).
        // GW_GLOW widens the halo for a dreamier hover.
        float airborne = 1.0 - settle;
        effect += vec3(0.20, 0.62, 0.50) * xcGlow(ap, body, 0.045 * GW_GLOW)
                  * airborne * 0.10;
    }

    // ---- MANDATORY composite : additive, luminous-on-dark, text legible ----
    effect = max(effect, vec3(0.0));

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (water, ripples,
    // lotus, and dragonfly alike) so the feeling reads at a glance — cool/glassy
    // (-1) through the authored jade-cyan (0) to warm/tender (+1). Default 0 =
    // identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;
    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}