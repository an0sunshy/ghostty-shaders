// 楓橋夜泊 (Fēngqiáo Yè Bó) — Night Mooring at Maple Bridge — 張繼 (Zhang Ji), Tang
//   月落烏啼霜滿天，江楓漁火對愁眠。
//   "The moon sets, a crow cries, frost fills the sky;
//    riverside maples and fishing-fires keep watch over sleepless grief."
//
// A cold night harbor. The scene composites, from back to front:
//   - a thin frost-haze band (霜滿天) drifting slowly across the upper sky,
//   - a pale cold moon-disc easing DOWNWARD at the left edge (月落, the moon
//     setting),
//   - a few SCATTERED warm ember fishing-fires (漁火) low on the dark river:
//     a near boat lower/brighter/larger, two farther ones higher, smaller
//     and dimmer — they recede across the water rather than standing in a
//     tidy row, each flickering and swaying gently,
//   - each fire's wavering vertical REFLECTION on the rippling water below
//     it, stretched and broken by a scrolling UV ripple field; the near
//     fire's reflection reaches deepest into the river.
// Most of the frame — especially the center where terminal text sits — stays
// near-black teal so glyphs read cleanly (留白). Light is concentrated in the
// sparse fires + their reflections, a faint sky band, and the sinking moon.
//
// Palette: deep teal-black river #04100f, ember-orange fires #ffae57,
//          cold moon-silver #cfe0ff.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls.
//   GW_MOOD    — global warm/cool tint over the whole harbor (frost, moon,
//                fires, reflections alike): -1 cold/blue .. 0 neutral .. +1 warm.
//   GW_ENERGY  — motion agitation: scales fire sway/flicker, reflection chop
//                and horizon shimmer AMPLITUDES (not the oscillator rates), so
//                low = still & glassy, high = restless water. 0.3 .. 1 .. 2.
//   GW_DENSITY — fill vs 留白: scales frost-band, moon, fire and reflection
//                coverage/alpha so >1 = lusher, <1 = sparser. 0.3 .. 1 .. 1.8.
//   GW_GLOW    — bloom/softness: scales glow radii and soft-edge widths so
//                >1 = dreamier halos, <1 = crisper points. 0.6 .. 1 .. 2.5.
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

float fqHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float fqNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = fqHash(i);
    float b = fqHash(i + vec2(1.0, 0.0));
    float c = fqHash(i + vec2(0.0, 1.0));
    float d = fqHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fqFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * fqNoise(p); p *= 2.05; a *= 0.5; }
    return v;
}

// Soft round point glow in aspect-corrected space. Returns 0..1.
float fqGlow(vec2 p, vec2 c, float r) {
    float d = length(p - c);
    return exp(-d * d / max(r * r, 1e-4));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                 // host is top-origin: uv.y = 1 at top

    // Sample the terminal glyph layer with the UNFLIPPED coord.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // Aspect-correct so circular glows stay round on any window shape.
    float aspect = iResolution.x / iResolution.y;
    vec2 ap = vec2(uv.x * aspect, uv.y);   // aspected position

    // Seamless looping clocks. Never feed raw iTime to fast oscillators.
    float tSlow = mod(iTime, 600.0);   // very slow: moon set + sky drift
    float tFlick = mod(iTime, 60.0);   // fire flicker / sway / ripple

    // GW_ENERGY drives motion AGITATION (amplitudes), never oscillator rates —
    // scaling a rate would teleport elements when the dial is dragged. eAmp is
    // exactly 1.0 at the default so authored motion is untouched; eExtra grows
    // only ABOVE default to add restless water/flicker on top.
    float eAmp   = 0.45 + 0.55 * GW_ENERGY;        // 1.0 at GW_ENERGY=1
    float eExtra = max(GW_ENERGY - 1.0, 0.0);      // 0.0 at/below default

    vec3 effect = vec3(0.0);

    // ---- 霜滿天 : a thin frost-haze band drifting slowly across the sky ----
    // A single horizontal band high on screen (uv.y ~ 0.80), feathered top and
    // bottom, textured with fbm that scrolls slowly leftward. Cold silver tint.
    // Kept dim and narrow so the upper sky still reads mostly dark.
    //
    // The fbm haze is only visible inside the feathered band; outside it `band`
    // is exactly 0 and the whole term multiplies away. Gate the fbm on `band`
    // so the ~75% of pixels outside the band skip the noise entirely (lossless).
    {
        float bandCenter = 0.80;
        // GW_GLOW softens/sharpens the band's feathered edges (its soft-edge
        // half-width). Default 1.0 keeps the authored 0.13 feather.
        float bandHalf   = 0.13 * GW_GLOW;
        float band = smoothstep(bandHalf, 0.0, abs(uv.y - bandCenter));
        if (band > 0.0) {
            // Scrolling fbm haze. Slow drift via fract is float-safe (monotone).
            float drift = fract(tSlow * (1.0 / 600.0)) * 2.0;
            float haze = fqFbm(vec2(uv.x * 3.2 - drift, uv.y * 2.4 + 5.0));
            haze = smoothstep(0.35, 0.95, haze);
            // Gentle breathing so the frost seems to thicken and thin.
            float breath = 0.72 + 0.28 * sin(mod(iTime, 47.0) * 0.1337);
            vec3 frostCol = vec3(0.62, 0.72, 0.86);   // cold moon-silver
            // GW_DENSITY scales how much frost fills the sky (its coverage/alpha):
            // >1 thicker 霜滿天, <1 a clearer sky. Default 1.0 = authored 0.16.
            effect += frostCol * band * haze * breath * 0.16 * GW_DENSITY;
        }
    }

    // ---- 月落 : a pale cold moon easing DOWNWARD at the left edge ----
    // Disc + soft halo. Its vertical position sinks slowly over the long
    // cycle (sets toward the horizon), staying near the left margin so the
    // center is free for text.
    {
        float moonX = 0.135;
        // Sink from y≈0.86 down toward y≈0.58 over the slow loop, then a
        // smooth return. Triangle-ish via a single slow sine keeps it seamless.
        float sink = 0.72 + 0.14 * cos(mod(iTime, 600.0) * (6.2831853 / 600.0));
        vec2 moonC = vec2(moonX * aspect, sink);
        // GW_GLOW grows the disc + halo radii: >1 a softer, dreamier moon,
        // <1 a crisper disc. Default 1.0 keeps the authored 0.045 / 0.16 radii.
        float disc = fqGlow(ap, moonC, 0.045 * GW_GLOW);
        disc = smoothstep(0.25, 1.0, disc);        // crisp-ish core
        float halo = fqGlow(ap, moonC, 0.16 * GW_GLOW) * 0.45;
        // The moon dims a touch as it sinks (lower = more atmospheric veil).
        float moonDim = mix(0.55, 1.0, smoothstep(0.58, 0.86, sink));
        vec3 moonCol = vec3(0.81, 0.88, 1.00);     // cold moon-silver #cfe0ff
        // GW_DENSITY scales the moon's presence (its coverage/alpha) alongside
        // the rest of the scene's fill. Default 1.0 = authored.
        effect += moonCol * (disc * 0.60 + halo * 0.32) * moonDim * GW_DENSITY;
    }

    // ---- river ripple field (drives reflections + horizon shimmer) ----
    // A directional, scrolling fbm gives a horizontal-displacement field that
    // makes the reflections waver and stretch. Stronger lower down (closer
    // water surface = larger apparent ripples).
    //
    // The ripple field is ONLY consumed in the water region: the fire
    // reflections live below their surfaces (highest surfaceY = 0.560) and the
    // horizon shimmer feathers around uv.y = 0.46. Above the highest reflection
    // surface nothing reads it, so gate both fbm calls behind a cheap water-band
    // test — the entire sky half (~45% of pixels) skips two 4-octave fbm calls.
    // Reuse `ripple` for the reflection chop, so only `rippleDisp` and `ripple`
    // need to survive the gate.
    float rippleDisp = 0.0;
    float ripple = 0.5;
    bool inWater = uv.y < 0.58;        // a hair above the highest surfaceY (0.560)
    if (inWater) {
        float rippleScroll = fract(tFlick * (1.0 / 60.0)) * 3.0;
        ripple = fqFbm(vec2(uv.x * 7.0, uv.y * 14.0 - rippleScroll));
        float ripple2 = fqFbm(vec2(uv.x * 3.5 + 9.0, uv.y * 22.0 + rippleScroll * 0.6));
        rippleDisp = (ripple - 0.5) + 0.4 * (ripple2 - 0.5);
    }

    // ---- 漁火 : scattered warm fishing-fires + wavering reflections ----
    // Three fires moored at different points across the river. They are NOT
    // in a tidy row: a near boat sits low / large / bright on the right, and
    // two farther boats sit higher / smaller / dimmer, receding into the dark.
    // Per-fire constants (X, surface Y, scale, brightness) give the scatter;
    // the loop bound stays constant for portability.
    const int NLIGHTS = 3;
    for (int i = 0; i < NLIGHTS; i++) {
        float fi = float(i);

        // Scattered, irregular placement. baseX avoids dead center; baseY is
        // the water-surface height of this boat (higher = farther up-river).
        // scale shrinks the farther boats; bright dims them — together they
        // read as receding distance, deepening the lonely 對愁眠 mood.
        float baseX, baseY, scale, bright;
        if (i == 0) {        // far boat, up-left of center, small + faint
            baseX = 0.305; baseY = 0.520; scale = 0.74; bright = 0.62;
        } else if (i == 1) { // mid boat, slightly farther, dimmest
            baseX = 0.560; baseY = 0.560; scale = 0.62; bright = 0.50;
        } else {             // near boat, low-right, large + bright
            baseX = 0.790; baseY = 0.435; scale = 1.00; bright = 1.00;
        }
        // The shared water surface sits a touch below the nearest boat so the
        // reflections all read as being ON one continuous river plane.
        float surfaceY = baseY;

        // Per-fire phase offset so they flicker/sway independently.
        float ph = fi * 2.3994;
        // Gentle horizontal sway of the boat/lamp — this scene's lead motion.
        // GW_ENERGY scales the sway/bob/flicker AMPLITUDES (eAmp, =1 at default)
        // and adds a slow shared lateral gust only ABOVE default (eExtra), so the
        // water reads still & glassy when low and restless when high — without
        // ever changing the oscillator rates (which would teleport the lamps).
        float sway = 0.012 * sin(mod(iTime, 41.0) * (0.45 + 0.11 * fi) + ph) * eAmp
                   + 0.010 * sin(mod(iTime, 29.0) * 0.5 + ph) * eExtra;
        float fireY = baseY + 0.018 * sin(mod(iTime, 53.0) * 0.3 + ph * 1.7) * eAmp;
        vec2 fireC = vec2((baseX + sway) * aspect, fireY);

        // Flicker: combine two incommensurate sines + a noise wobble so it
        // never looks like a clean pulse. Clamped to stay positive. The AC
        // wobble depth scales with eAmp (calm steady glow <-> agitated guttering
        // flame); the DC base 0.70 is untouched so default brightness holds.
        float fl = 0.70
                 + 0.20 * sin(mod(iTime, 17.0) * (3.1 + 0.7 * fi) + ph) * eAmp
                 + 0.16 * sin(mod(iTime, 23.0) * (5.3 + 0.5 * fi) + ph * 2.1) * eAmp
                 + 0.10 * (fqNoise(vec2(tFlick * 1.7 + fi * 13.0, fi)) - 0.5) * 2.0 * eAmp;
        fl = clamp(fl, 0.30, 1.25) * bright;

        // The ember itself: bright warm core + softer warm halo. Both scale
        // with the boat's distance so far lamps are visibly smaller. GW_GLOW
        // grows the core + halo radii for dreamier/crisper embers (default 1.0).
        float core = fqGlow(ap, fireC, 0.018 * scale * GW_GLOW);
        float glow = fqGlow(ap, fireC, 0.060 * scale * GW_GLOW) * 0.50;
        vec3 emberCol = vec3(1.00, 0.62, 0.28);    // ember-orange #ffae57-ish
        vec3 coreCol  = vec3(1.00, 0.78, 0.46);
        // GW_DENSITY scales the fires' fill (their alpha) so the river carries
        // more/fewer glowing points of light. Default 1.0 = authored.
        effect += (coreCol * core + emberCol * glow) * fl * GW_DENSITY;

        // --- wavering vertical reflection on the water (below surfaceY) ---
        // Only contributes below the fire. Horizontal distance to the fire's
        // column is perturbed by the ripple field so the streak snakes and
        // stretches. Brightness falls off with depth; near boats (scale~1)
        // throw a longer reflection than distant ones.
        float below = smoothstep(0.0, 0.05, surfaceY - uv.y);   // 0 above fire
        if (below > 0.0) {
            float depth = (surfaceY - uv.y);                    // >=0 below fire
            // Ripple displacement grows with depth → reflection stretches/wavers
            // markedly the deeper it falls, like a lamp doubled on moving water.
            // GW_ENERGY scales this wavering AMPLITUDE (eAmp, =1 at default): low
            // energy = a near-straight, glassy reflection; high = a snaking one.
            float disp = rippleDisp * (0.025 + 0.22 * depth) * eAmp;
            float colX = (baseX + sway) * aspect + disp;
            float dx = abs(ap.x - colX);
            // Narrow vertical streak; widen with depth as the reflection smears.
            // GW_GLOW scales the streak width (its soft Gaussian radius) so it
            // blooms softer/crisper with the rest of the scene. Default 1.0.
            float width = (0.011 + 0.07 * depth) * scale * GW_GLOW;
            float streak = exp(-(dx * dx) / max(width * width, 1e-4));
            // Vertical falloff: nearer boats reach deeper into the river.
            float vfall = exp(-depth * (3.4 / scale));
            // Ripple chops the streak into broken travelling glints.
            float chop = 0.45 + 0.75 * (ripple - 0.35);
            chop = clamp(chop, 0.0, 1.3);
            vec3 reflCol = vec3(0.95, 0.55, 0.26);
            // GW_DENSITY scales the reflection's fill (alpha). Default 1.0.
            effect += reflCol * streak * vfall * chop * fl * below * 0.65 * GW_DENSITY;
        }
    }

    // ---- faint cold cast on the open water surface near the horizon ----
    // A whisper of moon-silver right where the dark river meets the far bank
    // anchors the water plane without lifting the dark center. Very subtle.
    // surf is 0 outside uv.y ∈ (0.40, 0.52), which is inside the water gate, so
    // rippleDisp is already populated there.
    {
        float horizon = 0.46;
        // GW_GLOW softens/sharpens the shimmer band's feathered half-width.
        float surf = smoothstep(0.06 * GW_GLOW, 0.0, abs(uv.y - horizon));
        // GW_ENERGY scales the shimmer's AC swing (eAmp, =1 at default) around
        // its 0.5 mean — glassy when calm, livelier when high. Rate untouched.
        float shimmer = 0.5 + 0.5 * eAmp * sin(mod(iTime, 31.0) * 0.5 + uv.x * 18.0 + rippleDisp * 4.0);
        effect += vec3(0.40, 0.52, 0.66) * surf * shimmer * 0.04;
    }

    // ---- MANDATORY composite : additive, luminous-on-dark, text legible ----
    effect = max(effect, vec3(0.0));

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (frost, moon, fires
    // and reflections alike) so the feeling reads at a glance — cold/bleak (-1)
    // through the authored teal-silver (0) to warm/tender (+1). Default 0 =
    // identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;
    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}