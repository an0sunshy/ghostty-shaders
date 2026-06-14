// 秋夕 (Qiū Xī) — Autumn Night — 杜牧 (Du Mu), Tang
//   輕羅小扇撲流螢，天階夜色涼如水。
//   "With a light silk fan she swats at the drifting fireflies;
//    the night on the stone steps is cool as water."
//
// A cool autumn palace night, very sparse, maximal 留白. From back to front:
//   - 牽牛織女 : a sparse scatter of cold pinprick stars high on screen,
//     two slightly brighter and PAIRED (the Herd-boy and Weaver-girl),
//     holding steady far above,
//   - 涼如水 : a whisper of water-cool blue on the stone steps low on the
//     frame — a faint cold cast, never a wash,
//   - 流螢 : 6 fireflies wandering the lower-middle on lazy Lissajous loops,
//     each a soft green-gold bloom that BREATHES (sine-pulsed opacity),
//   - 輕羅小扇 : a faint pale silk fan-arc that sweeps in occasionally; the
//     nearest firefly is brushed by its leading edge and DARTS away (撲流螢).
// The center stays near-black indigo so terminal text reads cleanly. Light is
// concentrated in the wandering green points, the high paired stars, and the
// brief fan sweep — an enormous still negative space lies between low and high.
//
// Palette: indigo-black ground #0c0f1a, firefly green-gold #c8e07a→#f0e8a0,
//          stars cold white-blue #e8f0ff, fan pale silk #e6ecff.
//
// Four shared "feeling" dials (GW_MOOD/ENERGY/DENSITY/GLOW) tune warmth,
// firefly+star agitation, sky/firefly fill, and bloom; all-default is the
// authored look.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls.
//   GW_MOOD    — global warm/cool tone over the whole night (cool stars/steps
//                vs a warmer, tenderer dusk).
//   GW_ENERGY  — agitation of the firefly wander + star twinkle AMPLITUDE
//                (still/meditative .. lively), never the oscillator rates.
//   GW_DENSITY — how full the sky and firefly field read vs 留白 (sparse..lush).
//   GW_GLOW    — bloom/softness of every point (crisp pinpricks .. dreamy haze).
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

float qxHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float qxNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = qxHash(i);
    float b = qxHash(i + vec2(1.0, 0.0));
    float c = qxHash(i + vec2(0.0, 1.0));
    float d = qxHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Soft round point glow in aspect-corrected space. Returns 0..1.
float qxGlow(vec2 p, vec2 c, float r) {
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
    float TAU = 6.2831853;
    float tStar = mod(iTime, 120.0);   // slow stellar twinkle
    float tFan  = mod(iTime, 24.0);    // fan sweep cycle (24s loop)
    float fanPhase = tFan / 24.0;      // 0..1 across the sweep cycle

    vec3 effect = vec3(0.0);

    // ---- 牽牛織女 : cold pinprick stars high on screen, two brighter+paired
    // A sparse grid in the UPPER band only (uv.y > ~0.66) so the stars hold
    // far above the low fireflies, leaving the center empty. ~9% of cells
    // fire. The two paired stars are drawn explicitly, slightly brighter,
    // close together near the top — the Herd-boy and Weaver-girl across the
    // Milky Way. All stars hold steady (only a faint twinkle), per the brief.
    {
        vec3 starCol = vec3(0.91, 0.94, 1.00);   // cold white-blue #e8f0ff
        // Scattered field.
        vec2 g = uv * vec2(16.0, 11.0);
        vec2 cell = floor(g);
        vec2 fpart = fract(g);
        float h = qxHash(cell);
        // GW_DENSITY: lower the keep-threshold so MORE cells fire (a lusher
        // sky) or raise it for sparser 留白. density=1 keeps the authored 0.91.
        float starThresh = clamp(0.91 - (GW_DENSITY - 1.0) * 0.10, 0.05, 0.985);
        if (h > starThresh) {
            vec2 sp = vec2(fract(h * 17.3), fract(h * 31.7));
            float cellAspect = aspect * (11.0 / 16.0);
            float sd = length((fpart - sp) * vec2(cellAspect, 1.0));
            // Confine to the upper sky; fade out below ~0.66 so none stray
            // into the firefly zone or the empty center.
            float high = smoothstep(0.62, 0.74, uv.y);
            // GW_ENERGY scales the twinkle AMPLITUDE (the depth of the breath),
            // not its rate, so dialing it reads as calm<->lively without making
            // stars jump. eAmp = 1.0 at default.
            float eAmp = 0.45 + 0.55 * GW_ENERGY;
            float tw = 0.62 + 0.38 * eAmp * sin(tStar * (0.4 + h * 1.6) + h * TAU);
            // GW_GLOW softens the pinprick.
            float s = smoothstep(0.060 * GW_GLOW, 0.0, sd) * tw * high * 0.55;
            effect += starCol * s;
        }
        // The paired stars — drawn explicitly, near the top, close together
        // and a touch brighter so the eye reads them as a pair. A very faint
        // twinkle keeps them alive without drifting.
        vec2 vega = vec2(0.430 * aspect, 0.880);   // 織女 (Weaver, left)
        vec2 alta = vec2(0.560 * aspect, 0.840);   // 牽牛 (Herd-boy, right)
        // GW_ENERGY scales the pair's twinkle depth (amplitude), not its rate.
        float eAmpP = 0.45 + 0.55 * GW_ENERGY;
        float twV = 0.80 + 0.20 * eAmpP * sin(tStar * 0.37 + 1.1);
        float twA = 0.80 + 0.20 * eAmpP * sin(tStar * 0.31 + 3.7);
        // GW_GLOW softens both the bright heart and the halo of the pair.
        float pv = qxGlow(ap, vega, 0.011 * GW_GLOW) * twV;
        float pa = qxGlow(ap, alta, 0.011 * GW_GLOW) * twA;
        // Tiny soft halo so the pair reads as the brightest points up high.
        pv += qxGlow(ap, vega, 0.030 * GW_GLOW) * 0.18 * twV;
        pa += qxGlow(ap, alta, 0.030 * GW_GLOW) * 0.18 * twA;
        effect += starCol * (pv + pa) * 0.95;
    }

    // ---- 涼如水 : water-cool blue on the stone steps, low on the frame ----
    // A faint cold cast near the bottom suggesting the dew-cool stone steps.
    // Feathered band, very dim, with a slow horizontal shimmer so it reads as
    // "cool as water" without lifting the dark center. Kept well below the
    // text zone.
    {
        float stepCenter = 0.085;
        // GW_GLOW widens the cool band's feather (a dreamier, higher haze).
        float band = smoothstep(0.18 * GW_GLOW, 0.0, abs(uv.y - stepCenter));
        float shimmer = 0.55 + 0.45 * sin(mod(iTime, 37.0) * 0.45 + uv.x * 7.0);
        // Gentle large-scale mottling so the stone isn't a flat strip.
        float mottle = 0.6 + 0.4 * qxNoise(vec2(uv.x * 4.0, uv.y * 3.0 + 2.0));
        vec3 coolCol = vec3(0.30, 0.46, 0.66);   // water-cool blue
        // GW_DENSITY scales how much the cool cast fills the steps (留白 vs lush).
        effect += coolCol * band * shimmer * mottle * 0.065 * GW_DENSITY;
    }

    // ---- 輕羅小扇 : the silk fan-arc, sweeping in occasionally ----
    // For most of the loop the fan is absent (sweepEnv = 0). Once per cycle it
    // arcs across — a thin pale crescent whose center swings left→right then
    // fades. We compute its leading-edge X here so the nearest firefly can be
    // brushed by it below. The arc is a faint ring segment, deliberately soft.
    // sweepEnv ramps up over the first ~30% of the cycle and back down, so the
    // fan is briefly present then gone — "she idly bats once" (撲流螢).
    float sweepEnv = smoothstep(0.0, 0.10, fanPhase) * smoothstep(0.42, 0.20, fanPhase);
    // The small round fan is a thin luminous crescent that swings up-and-left
    // toward the nearest firefly. Its CENTER travels along a short path near
    // the lower-right; the crescent is a tight arc (rim of the round fan) of a
    // small fixed radius, so it reads as 小扇 (a little fan), not a fog plume.
    vec2 fanStart  = vec2(0.78 * aspect, 0.230);
    vec2 fanEnd    = vec2(0.62 * aspect, 0.330);
    float fanSwing = smoothstep(0.05, 0.40, fanPhase);
    vec2 fanCenter = mix(fanStart, fanEnd, fanSwing);
    float fanAng   = mix(-0.55, 0.65, fanSwing);   // the fan tilts as it swings
    float fanRad   = 0.060;                          // small round fan
    // Leading edge point of the fan (where it would brush a firefly): the rim
    // in the direction the fan is tilted (up-and-left).
    vec2 fanDir = vec2(-sin(fanAng), cos(fanAng));
    vec2 fanTip = fanCenter + fanDir * fanRad;
    {
        // Thin crescent: a tight ring at radius fanRad around fanCenter, with
        // the leading half (facing fanDir) brightest — a silk rim catching the
        // light. No volumetric fill, so it stays a crisp stroke.
        vec2 rel = ap - fanCenter;
        float rd  = length(rel);
        // GW_GLOW widens the silk rim (smaller falloff coefficient = softer).
        float ring = exp(-pow((rd - fanRad) * (26.0 / GW_GLOW), 2.0));   // crisp silk rim
        // Bias the rim brightness toward the leading direction (a crescent,
        // not a full ring): dot of the unit radial with fanDir.
        float facing = dot(normalize(rel + 1e-4), fanDir);
        float crescent = smoothstep(-0.2, 0.95, facing);
        vec3 fanCol = vec3(0.88, 0.91, 1.00);   // pale silk #e6ecff
        effect += fanCol * ring * crescent * sweepEnv * 0.42;
    }

    // ---- 流螢 : wandering, breathing fireflies on lazy Lissajous loops ----
    // 6 fireflies in the lower-middle. Each wanders on its own slow Lissajous
    // (two incommensurate sines per axis) so the paths never repeat tidily,
    // and breathes (a sine-pulsed opacity) — brightening and dimming as it
    // drifts. Core is gold, halo greener: a green-gold bloom. The NEAREST
    // firefly (index 0) is the one the fan reaches: when the fan tip passes
    // close, it is knocked sideways and darts away, then eases back.
    const int NFLY = 6;
    // Slow wander clocks, all wrapped for float-safety.
    float tw1 = mod(iTime, 53.0);
    float tw2 = mod(iTime, 71.0);
    float tw3 = mod(iTime, 89.0);
    for (int i = 0; i < NFLY; i++) {
        float fi = float(i);
        // Per-firefly seeds for path shape / center / speed / phase.
        float s0 = qxHash(vec2(fi, 1.0));
        float s1 = qxHash(vec2(fi, 7.0));
        float s2 = qxHash(vec2(fi, 13.0));
        float ph = fi * 1.7 + s0 * TAU;

        // Loop center scattered across the lower-middle band (uv.y ~0.22..0.46),
        // avoiding the dead center column a little for 留白.
        float cx = 0.18 + 0.64 * s0;
        float cy = 0.24 + 0.20 * s1;
        // Lissajous wander — gentle amplitudes, slow incommensurate rates.
        // GW_ENERGY scales the wander AMPLITUDE (how far each firefly roams),
        // never the rates — so low energy = nearly-still drifting points, high
        // energy = restless darting, without the path teleporting. eAmp = 1.0
        // at default.
        float eAmp = 0.45 + 0.55 * GW_ENERGY;
        float ax = (0.085 + 0.05 * s2) * eAmp;
        float ay = (0.060 + 0.04 * s0) * eAmp;
        float rxA = 0.21 + 0.10 * s1;
        float ryA = 0.17 + 0.09 * s2;
        float wx = cx + ax * sin(tw1 * rxA + ph) + 0.35 * ax * sin(tw3 * (rxA * 1.7) + ph * 1.3);
        float wy = cy + ay * sin(tw2 * ryA + ph * 1.4) + 0.35 * ay * cos(tw1 * (ryA * 1.9) + ph);

        // ---- fan interaction: the nearest firefly (i==0) darts off the fan.
        // When the fan is present and its tip is near this firefly, push it
        // away from the tip along the tip→firefly direction, then let it
        // settle. Only firefly 0 reacts (輕羅小扇撲流螢 — one is brushed).
        if (i == 0) {
            vec2 here = vec2(wx * aspect, wy);
            vec2 away = here - fanTip;
            float dd = length(away);
            // Proximity kick, gated by the fan's presence this cycle.
            float kick = sweepEnv * exp(-dd * dd / 0.010);
            vec2 dir = away / max(dd, 1e-3);
            wx += dir.x * kick * 0.10;
            wy += dir.y * kick * 0.10;
        }

        vec2 flyC = vec2(wx * aspect, wy);

        // Breathing opacity — each firefly pulses on its own phase, never
        // fully out (a living glow). Two incommensurate sines + clamp.
        float breath = 0.55
                     + 0.34 * sin(mod(iTime, 19.0) * (1.7 + 0.6 * s1) + ph)
                     + 0.18 * sin(mod(iTime, 13.0) * (2.3 + 0.5 * s2) + ph * 2.0);
        breath = clamp(breath, 0.10, 1.05);

        // Green-gold bloom: small gold core inside a greener soft halo.
        // GW_GLOW softens both the core and the halo (dreamier fireflies).
        float core = qxGlow(ap, flyC, 0.010 * GW_GLOW);
        float halo = qxGlow(ap, flyC, 0.034 * GW_GLOW) * 0.55;
        vec3 coreCol = vec3(0.94, 0.91, 0.63);   // gold #f0e8a0
        vec3 haloCol = vec3(0.78, 0.88, 0.48);   // green-gold #c8e07a
        // GW_DENSITY modulates how present the firefly field reads: the lone
        // fan-brushed firefly (i==0, 撲流螢) always stays as a fixed point of
        // life, but the rest fade toward 留白 below 1.0 and bloom fuller above.
        // density=1 leaves every firefly at the authored brightness.
        float flyCov = (i == 0) ? 1.0 : clamp(0.40 + 0.60 * GW_DENSITY, 0.0, 1.6);
        effect += (coreCol * core + haloCol * halo) * breath * flyCov;
    }

    // ---- MANDATORY composite : additive, luminous-on-dark, text legible ----
    effect = max(effect, vec3(0.0));

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (stars, the cool
    // steps, the fireflies, and the fan alike) so the feeling reads at a glance
    // — cold/bleak (-1) through the authored cool indigo night (0) to a warmer,
    // tenderer dusk (+1). Default 0 = identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;
    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}