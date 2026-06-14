// 次北固山下 (Cì Běigù Shān Xià) — Mooring Below Beigu Mountain — 王灣 (Wáng Wān), Tang
//   海日生殘夜，江春入舊年。鄉書何處達，歸雁洛陽邊。
//   "The sea-sun is born from the dying night; spring on the river breaks into
//    the old year. Where will my letter home arrive? — Carry it, returning
//    geese, to Luoyang's side."
//
// The canon's only SUNRISE — the deliberate inverse of its many sunsets. A wide
// calm river near the sea at daybreak. Composited back to front:
//   - a sky gradient that LIGHTENS over the long cycle: near-black indigo
//     zenith draining to dawn-indigo and a pale-rose band at the waterline
//     (殘夜 — the dying night), brightest exactly where the sun is born;
//   - a warm red-gold sun DISC that eases UPWARD (生 — born from the sea) out
//     of a horizontal sea-glow band low in the frame; its reflection a short
//     shimmering vertical streak on rippling water directly below it;
//   - a faint, still single sail-triangle moored low (the lone boat);
//   - high in the frame, ONE small luminous goose glyph (歸雁) drifting slowly
//     UP toward the top-right corner on a gentle wing-bob, fading at the edge —
//     a lone bird returning north toward Luoyang.
// The center stays open dawn-sky for text (留白); light pools at the lower
// waterline and the single rising disc, with the goose a faint counter-note high.
//
// Palette: rising sun #ff8c42→#fef1d1, dawn-rose horizon #f6c5be,
//          draining night-indigo zenith #0a1024, pale goose #e8f0ff.
//
// Four "feeling" dials tune the scene from one set of controls (all-default =
// authored look): GW_MOOD warms/cools the whole frame; GW_ENERGY scales the
// water-ripple and goose wing-beat AGITATION (not the sun's climb rate);
// GW_DENSITY scales the dawn-sky glow + sail/goose fill (留白); GW_GLOW scales
// the sun's corona, reflection and goose-glint bloom radii.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls. In THIS dawn scene they drive:
//   MOOD    — global warm/cool tone over sky, sun, sail and goose alike;
//   ENERGY  — agitation amplitude: water-ripple wander + the goose's wing-beat
//             and bob (the rates — sun's climb, ripple scroll — stay fixed);
//   DENSITY — fill vs 留白: the dawn-sky glow plus the sail/goose presence;
//   GLOW    — bloom/softness: the sun's corona, reflection streak and the
//             goose's glint radii / soft-edge widths.
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

float cbHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float cbNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = cbHash(i);
    float b = cbHash(i + vec2(1.0, 0.0));
    float c = cbHash(i + vec2(0.0, 1.0));
    float d = cbHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float cbFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * cbNoise(p); p *= 2.05; a *= 0.5; }
    return v;
}

// Soft round point glow in aspect-corrected space. Returns 0..1.
float cbGlow(vec2 p, vec2 c, float r) {
    float d = length(p - c);
    return exp(-d * d / max(r * r, 1e-4));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                 // host is top-origin: uv.y = 1 at top

    // Sample the terminal glyph layer with the UNFLIPPED coord.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // Aspect-correct so the disc and glows stay round on any window shape.
    float aspect = iResolution.x / iResolution.y;
    vec2 ap = vec2(uv.x * aspect, uv.y);

    // Seamless looping clocks. Never feed raw iTime to fast oscillators.
    // The sun's birth is the LEAD motion, so its loop is short enough to read as
    // a continuous climb within a few seconds (≈40 s, seamless via cosine); the
    // ripple is faster still. The goose rides its own clock below.
    float tBirth = mod(iTime, 40.0);    // sun's birth + sky drain (lead motion)
    float tRip   = mod(iTime, 60.0);    // water ripple / shimmer

    // Birth phase 0..1..0 over the loop: ease up then ease back (seamless via
    // cosine). 0 = sun still in the sea (night), 1 = fully risen above the water.
    float birth = 0.5 - 0.5 * cos(tBirth * (6.2831853 / 40.0));

    vec3 effect = vec3(0.0);

    // ---- 殘夜 : the sky LIGHTENS over the cycle, brightest at the waterline ----
    // We do NOT wash the whole frame. The zenith (center, where text sits) holds
    // near iBackgroundColor; only the lower band near the water gains a faint
    // dawn glow that swells as the sun is born. uv.y = 0 is the very bottom.
    {
        // Vertical falloff: glow concentrated near the bottom waterline, decaying
        // upward. Center/zenith receive almost nothing so text stays legible.
        float low = smoothstep(0.55, 0.0, uv.y);     // 1 at bottom → 0 by mid-frame
        low = low * low;                              // tighten toward the waterline
        // The dawn swells with the sun's birth: dark at night, rose at sunrise.
        float dawn = mix(0.10, 1.0, birth);
        // Horizontal: brightest around the sun's column, gently wider near water.
        float sunX = 0.50;
        float horiz = exp(-pow(max(abs(uv.x - sunX), 1e-4), 2.0) * 3.0);
        horiz = 0.45 + 0.55 * horiz;                  // never fully dark off-axis
        // Dawn-rose at the waterline easing to indigo just above it.
        vec3 roseCol   = vec3(0.96, 0.62, 0.55);      // dawn-rose #f6c5be-warm
        vec3 indigoCol = vec3(0.10, 0.16, 0.34);      // dawn indigo
        vec3 skyCol = mix(indigoCol, roseCol, low);
        // GW_DENSITY: the dawn-sky glow is the scene's main fill; scaling it
        // makes the frame lusher (>1) or emptier 留白 (<1). Default 1 = authored.
        effect += skyCol * low * dawn * horiz * 0.30 * GW_DENSITY;
    }

    // ---- water ripple field (drives the sun's reflection + horizon shimmer) ----
    // Directional scrolling fbm gives a small horizontal-displacement field so the
    // sun's reflection wavers. Only the lower water region consumes it; the sky
    // half skips the fbm entirely (lossless).
    float waterY = 0.30;                 // calm river surface height
    float rippleDisp = 0.0;
    float ripple = 0.5;
    bool inWater = uv.y < waterY + 0.02;
    // GW_ENERGY scales AGITATION (the displacement AMPLITUDE of the ripple wander
    // and, below, the goose's wing-beat + bob), NOT the scroll/climb rates — so
    // dialling it reads as calm<->lively water and flight rather than the sun or
    // ripples jumping to new phases. Default (1.0) keeps the authored motion.
    float eAmp = 0.45 + 0.55 * GW_ENERGY;             // 1.0 at default
    if (inWater) {
        float scroll = fract(tRip * (1.0 / 60.0)) * 3.0;
        ripple = cbFbm(vec2(uv.x * 8.0, uv.y * 16.0 - scroll));
        float ripple2 = cbFbm(vec2(uv.x * 4.0 + 9.0, uv.y * 24.0 + scroll * 0.6));
        rippleDisp = ((ripple - 0.5) + 0.4 * (ripple2 - 0.5)) * eAmp;
    }

    // ---- 海日生 : the red-gold sun born from the sea, rising upward ----
    // The disc eases UP out of the water as `birth` grows: rising = the center's
    // uv.y INCREASES with time (uv.y = 1 is top). It starts half-drowned at the
    // waterline and lifts to sit just above it — the lead motion of the poem.
    float sunX = 0.50;
    float sunY = mix(waterY - 0.015, waterY + 0.135, birth);   // rises with birth
    vec2 sunC = vec2(sunX * aspect, sunY);
    float sunR = 0.060;
    {
        // Disc: warm core fading to gold rim. Crisp-ish edge via smoothstep on the
        // aspect-corrected radius so the disc reads as a solid body, not a blob.
        float d = length(ap - sunC);
        float disc = smoothstep(sunR, sunR * 0.62, d);          // 1 inside → 0 at rim
        // Radial body color: incandescent pale gold core → warm orange rim.
        float rr = clamp(d / sunR, 0.0, 1.0);
        vec3 coreCol = vec3(1.00, 0.94, 0.78);      // #fef1d1 pale gold core
        vec3 rimCol  = vec3(1.00, 0.55, 0.26);      // #ff8c42 rising-sun orange
        vec3 sunBody = mix(coreCol, rimCol, rr);
        // Soft outer corona so the disc bleeds warmly into the dawn.
        // GW_GLOW scales the bloom RADII so the sun reads crisper (<1) or
        // dreamier (>1); default 1 keeps the authored corona.
        float corona = cbGlow(ap, sunC, 0.16 * GW_GLOW) * 0.55
                     + cbGlow(ap, sunC, 0.34 * GW_GLOW) * 0.22;
        // The sun brightens as it clears the water (born from the dying night).
        float emerge = mix(0.45, 1.0, birth);
        // A horizon haze cuts the lower half of the disc where it meets the sea,
        // so it reads as RISING OUT of the water rather than floating free.
        float seaCut = smoothstep(waterY - 0.03, waterY + 0.02, uv.y);
        seaCut = mix(0.55, 1.0, seaCut);            // dim, not erase, below surface
        effect += sunBody * disc * emerge * seaCut;
        effect += rimCol  * corona * emerge;
    }

    // ---- the sun's shimmering vertical reflection on the rippling water ----
    // A short bright streak directly below the disc, broken and swayed by the
    // ripple field, deepening only a little (calm river). Falls within the water
    // gate so rippleDisp is populated.
    if (inWater) {
        float top = waterY;                          // reflection starts at surface
        float depth = top - uv.y;                    // >=0 below the surface
        if (depth > 0.0) {
            // Horizontal column wavers with the ripple field; widen with depth.
            float disp = rippleDisp * (0.02 + 0.30 * depth);
            float colX = sunX * aspect + disp;
            float dx = abs(ap.x - colX);
            float width = (0.030 + 0.10 * depth) * GW_GLOW;  // GW_GLOW softens the streak
            float streak = exp(-(dx * dx) / max(width * width, 1e-4));
            float vfall = exp(-depth * 6.0);         // short on a calm river
            float chop = 0.45 + 0.85 * (ripple - 0.30);
            chop = clamp(chop, 0.0, 1.4);
            float emerge = mix(0.45, 1.0, birth);
            vec3 reflCol = vec3(1.00, 0.60, 0.30);
            effect += reflCol * streak * vfall * chop * emerge * 0.85;
        }
    }

    // ---- the lone moored sail — a faint, still triangle low on the water ----
    // 江 (the river boat). Kept dim and small, off to one side so it anchors the
    // scene without competing with the sun or crowding the text center.
    {
        float sailX = 0.255;
        float sailBaseY = waterY + 0.010;            // sits on the water surface
        float sailH = 0.085;
        // Triangle: bright when uv.y is within the sail's height above the base,
        // and horizontal half-width shrinks linearly to the peak (a taut sail).
        float yy = (uv.y - sailBaseY) / sailH;       // 0 at base → 1 at peak
        if (yy > 0.0 && yy < 1.0) {
            float halfW = 0.045 * (1.0 - yy);         // taut leading edge
            float dxs = abs(uv.x - sailX) * aspect;
            float sail = smoothstep(halfW, halfW * 0.55, dxs);
            // Faint cool-warm wash so it reads as a pale sail catching dawn light.
            // GW_DENSITY scales its presence (part of the scene's fill); default 1.
            vec3 sailCol = vec3(0.70, 0.66, 0.66);
            effect += sailCol * sail * 0.18 * GW_DENSITY;
        }
    }

    // ---- 歸雁 : one lone homing goose drifting UP toward the top-right ----
    // A single small luminous bird, high in the frame, travelling UPWARD and to
    // the right (returning north toward Luoyang), fading as it nears the corner.
    // Rendered as a thin open "v" of two wing-strokes that BEAT as it flies — a
    // distant bird seen from below, evocative not literal (no body blob, so it
    // never reads as a solid triangle or a glyph).
    {
        // Drift across the upper sky on its own ≈26 s loop so the crossing is
        // visible within a few seconds yet seamless. gp is monotone 0..1.
        float gp = fract(mod(iTime, 26.0) * (1.0 / 26.0));
        float gx = mix(0.40, 0.86, gp);               // travels right
        float gy = mix(0.66, 0.93, gp);               // travels UP toward the top
        // Wing-beat: the chevron opens and closes as the goose flaps. Faster than
        // the drift, seamless via mod. Steeper droop = wings down mid-beat.
        // GW_ENERGY scales the beat's SWING and the bob AMPLITUDE (not the 2.3
        // flap rate) so the bird flaps calmly (<1) or vigorously (>1); the beat's
        // mean (0.30) is held fixed so default 1 leaves the flight authored.
        float beatOsc = 0.5 + 0.5 * sin(mod(iTime, 7.0) * 2.3);
        float beat = 0.30 + 0.34 * (0.5 + (beatOsc - 0.5) * eAmp);
        // Slight vertical bob synced loosely to the beat.
        float bob = 0.006 * eAmp * sin(mod(iTime, 7.0) * 2.3);
        vec2 gC = vec2(gx * aspect, gy + bob);
        vec2 lp = ap - gC;                            // local, aspect-corrected
        float wx = abs(lp.x);
        // Open chevron: each wing is the line y = +beat*|x| (a soft "v"), so the
        // bird points the way it travels. Distance to that line, with the stroke
        // fading out past the wingtips, gives two thin luminous wing marks.
        float wingSpan = 0.030;
        float lineY = beat * wx;
        float dToWing = abs(lp.y - lineY);
        float along = smoothstep(wingSpan, 0.0, wx);  // fade past the wingtips
        // Thin wing strokes only — no central body fill, so it stays bird-like.
        // GW_GLOW softens the wing stroke and the body glint radii (crisp<->dreamy).
        float bird = smoothstep(0.009 * GW_GLOW, 0.0, dToWing) * along;
        // A tiny faint glint where the wings meet (the body), kept small.
        bird += cbGlow(ap, gC, 0.006 * GW_GLOW) * 0.45;
        // Fade as it nears the top-right edge (receding into the dawn), but never
        // fully vanish mid-flight.
        float edgeFade = smoothstep(0.96, 0.80, gy) * smoothstep(0.92, 0.74, gx);
        edgeFade = clamp(edgeFade + 0.30, 0.0, 1.0);
        // GW_DENSITY scales the goose's presence (part of the scene's fill); 1 = authored.
        vec3 gooseCol = vec3(0.91, 0.95, 1.00);       // pale goose #e8f0ff
        effect += gooseCol * bird * edgeFade * 0.60 * GW_DENSITY;
    }

    // ---- MANDATORY composite : additive, luminous-on-dark, text legible ----
    effect = max(effect, vec3(0.0));

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (sky, sun, sail and
    // goose alike) so the feeling reads at a glance — cold/bleak (-1) through the
    // authored dawn (0) to warm/tender (+1). Default 0 = identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;
    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}