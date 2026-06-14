// 念奴嬌·赤壁懷古 (Niàn Nú Jiāo · Chìbì Huáigǔ) — Meditation on Red Cliff — 蘇軾 (Su Shi), Song
//   亂石穿空，驚濤拍岸，捲起千堆雪。
//   "Jagged rocks pierce the sky; startled breakers smash the shore,
//    rolling up a thousand drifts of snow."
//
// The grandest crashing-wave scene in the canon. Composited back-to-front:
//   - 亂石穿空 : a near-black ragged cliff rampart occupying the RIGHT third,
//     jutting up into the night sky with one bright vertical impact edge.
//   - 驚濤拍岸 : a turbulent foam band gated to the LOWER-LEFT water region,
//     advancing on a surge envelope. On each surge the leading foam edge
//     sweeps IN toward the fixed cliff x and SLAMS.
//   - 捲起千堆雪 : on impact, a radial burst of additive spray particles
//     launches UP the rock face, peaks, and rains back DOWN under gravity —
//     spray flung up like heaped snow against dark stone. The frame breathes
//     on a strike-and-retreat pulse; between hits the surge recedes and the
//     foam-line sinks.
//
// Motion direction (host renders UPRIGHT, uv.y=1 at TOP): foam advances
// rightward toward the cliff; spray launches UP (toward smaller uv.y values
// i.e. higher on screen) then falls DOWN as iTime advances. Verified by
// rendering t=1,5,9 frames.
//
// The upper-left sky and the CENTER stay near-black so terminal text reads
// cleanly (留白). Light is concentrated at the cliff impact edge, the foam
// band, and the spray plumes only.
//
// Palette: charcoal-black cliff #07080e, deep teal river #0a2630,
//          brilliant white-cyan foam #d8f4ff.
//
// PERFORMANCE: every heavy block (cliff fbm texture, foam fbm churn, the
// spray particle LOOP, the drifting mist) is GATED behind a cheap region
// test. The scene's light lives only in the right-third cliff, the lower
// water band, and the cliff-base spray plume — the vast majority of pixels
// (upper-left sky, dead center) hit none of those regions and skip all fbm
// and the loop entirely. Pixels that contributed ~0 still contribute ~0,
// so the gates are lossless. fbm octaves were trimmed 5->3 on the texture
// fields where the extra octaves vanish under the smoothstep thresholds.
//
// DIALS: four shared "feeling" knobs (neutral defaults = authored look):
//   GW_MOOD    — global warm/cool tone over the whole scene (cliff, foam, spray).
//   GW_ENERGY  — agitation of the lead motion: water-surface sway, foam churn,
//                and spray-plume turbulence AMPLITUDES (not the strike rate).
//   GW_DENSITY — how much foam/spray FILLS the water vs leaves it open (留白).
//   GW_GLOW    — bloom/softness of the spray motes, sheet, rim and impact flare.

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

float rcHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float rcNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = rcHash(i);
    float b = rcHash(i + vec2(1.0, 0.0));
    float c = rcHash(i + vec2(0.0, 1.0));
    float d = rcHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 3-octave fbm. Constant loop bound. Used everywhere in this scene: the
// silhouette profile, the churned foam, and the rock/mist textures are all
// smoothstep-thresholded, so octaves 4-5 of the old 5-octave fbm only added
// sub-pixel jitter below the threshold edge — dropping them is invisible.
float rcFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 3; i++) { v += a * rcNoise(p); p = p * 2.03 + 1.7; a *= 0.5; }
    return v;
}

// Soft round point glow in aspect-corrected space. Returns 0..1.
float rcGlow(vec2 p, vec2 c, float r) {
    float d = length(p - c);
    return exp(-d * d / max(r * r, 1e-4));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                 // host is top-origin: uv.y = 1 at top

    // Sample the terminal glyph layer with the UNFLIPPED coord.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // Aspect-correct so circular bursts stay round on any window shape.
    float aspect = iResolution.x / iResolution.y;
    vec2 ap = vec2(uv.x * aspect, uv.y);   // aspected position

    // Seamless looping clocks. Never feed raw iTime to fast oscillators.
    // The strike-and-retreat pulse is the heartbeat of the scene.
    float STRIKE = 4.2;                       // seconds per wave strike
    float tStrike = mod(iTime, STRIKE);       // 0..STRIKE within one pulse
    float ph = tStrike / STRIKE;              // 0..1 phase of the pulse
    float tFoam = mod(iTime, 60.0);           // foam churn / ripple scroll
    float tDrift = mod(iTime, 120.0);         // slow water drift

    // GW_ENERGY scales motion AGITATION (sway / turbulence AMPLITUDES), never
    // the oscillator RATES — so dragging the dial reads as calm<->lively water
    // instead of teleporting the surface and motes. eAmp = 1.0 at the default,
    // and eGust adds an extra plume turbulence that grows ONLY above default.
    float eAmp = 0.45 + 0.55 * GW_ENERGY;          // 1.0 at default
    float eGust = max(GW_ENERGY - 1.0, 0.0);       // 0 at/below default

    vec3 effect = vec3(0.0);

    // ---- geometry of the cliff base ----
    // The cliff occupies the right third. Its left face is a ragged, mostly
    // vertical silhouette around xCliff, perturbed by fbm so it looks like
    // broken rock (亂石). Everything to the RIGHT of the face is solid stone;
    // the impact line is the face itself.
    float xCliff = 0.66;                      // base cliff face x (uv space)
    // Ragged vertical profile: the face wanders with height. Carved, jagged.
    float rough = rcFbm(vec2(uv.y * 5.0 + 3.0, 7.0)) - 0.5;       // broad jag
    float rough2 = rcFbm(vec2(uv.y * 13.0 + 21.0, 2.0)) - 0.5;    // fine teeth
    float rough3 = rcFbm(vec2(uv.y * 27.0 + 44.0, 5.0)) - 0.5;   // jagged teeth
    float faceX = xCliff + rough * 0.085 + rough2 * 0.030 + rough3 * 0.016;
    // Stone mask: 1 inside the rock (right of the face), 0 in open water/sky.
    float stone = smoothstep(faceX - 0.006, faceX + 0.006, uv.x);

    // ---- water surface line (the shore the breakers smash against) ----
    // The open water sits in the lower-left. Its surface undulates gently and
    // rises toward the cliff base. Below this line is river; above is sky.
    float surfBase = 0.40;
    // Surface sway AMPLITUDE scaled by eAmp (GW_ENERGY): calm-flat water at low
    // energy, livelier heave at high — phase/rate unchanged so it never jumps.
    float surfWobble = (0.025 * sin(mod(iTime, 19.0) * 0.7 + uv.x * 9.0)
                      + 0.015 * sin(mod(iTime, 29.0) * 1.1 + uv.x * 17.0)) * eAmp;
    float waterY = surfBase + surfWobble + (rcFbm(vec2(uv.x * 4.0 + tDrift * 0.05, 9.0)) - 0.5) * 0.05;
    float water = smoothstep(waterY + 0.02, waterY - 0.02, uv.y);  // 1 below surface

    // ============================================================
    // 亂石穿空 : the black cliff rampart
    // ============================================================
    // The cliff is near-black charcoal that reads as a SILHOUETTE jutting up
    // into the sky. To make a near-black mass legible on a near-black field we
    // give it (a) a thin luminous rim that traces the jagged left face — the
    // edge catching sky/spray light — and (b) a faint cold internal sheen so
    // the body has rocky form. The bulk stays ≈ iBackgroundColor.
    //
    // GATE: every term here is multiplied by `stone` or by a thin rim mask
    // centered on faceX, all of which are zero unless uv.x is within ~0.025 of
    // the face or to its right. Far-left pixels (the open water / sky, the bulk
    // of the frame) get nothing from this block — skip the rock-texture fbm.
    float wetGrad = smoothstep(0.78, 0.30, uv.y);  // shared by rim/ledge
    if (uv.x > faceX - 0.03) {
        // Bright rim hugging the ragged face — the lit edge of the silhouette.
        // Brighter low (wet, foam-splashed) and fading up the rock (穿空). A
        // touch wider than a hairline so it reads as a fractured rock edge, not
        // a bolt. The rim wavers slightly in brightness up the face (broken teeth).
        float rim = smoothstep(0.024 * GW_GLOW, 0.0, abs(uv.x - faceX)) * stone;
        // Hard chopping into broken teeth so the edge looks fractured.
        float teeth = smoothstep(0.30, 0.85, rcNoise(vec2(uv.y * 24.0, 8.0)));
        teeth = 0.25 + 0.75 * teeth;
        vec3 rimCol = vec3(0.30, 0.42, 0.55);       // cold rock-edge sheen
        effect += rimCol * rim * teeth * (0.05 + 0.55 * wetGrad);

        // A second, fainter inner ledge a little inside the face — suggests a
        // stepped, broken rock profile rather than one clean edge.
        float ledgeX = faceX + 0.045 + 0.02 * (rcNoise(vec2(uv.y * 8.0 + 12.0, 3.0)) - 0.5);
        float ledge = smoothstep(0.012, 0.0, abs(uv.x - ledgeX)) * stone;
        effect += rimCol * ledge * 0.10 * (0.4 + 0.6 * wetGrad);

        // Faint internal sheen — broken-rock facets catching a little light, so
        // the rampart is a textured mass, not a flat cutout. Kept very dim.
        float rockTex = rcFbm(vec2(uv.x * 10.0 + 30.0, uv.y * 13.0));
        float facet = smoothstep(0.52, 0.95, rockTex) * stone
                    * smoothstep(faceX, faceX + 0.16, uv.x);   // stronger just inside face
        vec3 stoneCol = vec3(0.10, 0.15, 0.21);
        effect += stoneCol * facet * (0.12 + 0.30 * wetGrad);
    }

    // ---- impact edge brightness driven by the strike pulse ----
    // Distance to the ragged cliff face (in uv x). A thin bright vertical band
    // hugging the face, intensified on impact and only where rock meets water.
    float distFace = abs(uv.x - faceX);
    // Surge envelope: foam advances toward the cliff over the first ~65% of the
    // pulse, slams (peak) near ph~0.62, then recedes. A smooth asymmetric pulse.
    float approach = smoothstep(0.0, 0.62, ph);             // 0->1 advancing
    float retreat  = 1.0 - smoothstep(0.62, 1.0, ph);       // 1->0 receding
    float surge = approach * retreat;                       // 0..1 strike env
    surge = pow(max(surge, 1e-4), 0.6);                     // punchier peak

    // ============================================================
    // 驚濤拍岸 : turbulent foam band advancing on the surge
    // ============================================================
    // The foam lives in a band hugging the water surface in the lower-left,
    // advancing rightward toward the cliff. Its leading edge position is driven
    // by `surge` so it sweeps IN and SLAMS, then pulls back.
    //
    // GATE: the foam (band straddling the surface) and the teal river glow are
    // confined to the water region, which is the LOWER part of the frame
    // (uv.y below the surface band, ~0.56 and under). The upper sky has no
    // water at all. Skip the two foam-churn fbm calls for any pixel well above
    // the surface band — those pixels' foam contribution is identically zero.
    float foamEdge = mix(0.16, faceX + 0.01, surge);  // also used by spray origin
    if (uv.y < waterY + 0.18) {
        // Region: below the water surface band, left of the (moving) foam edge.
        float inWater = water * (1.0 - stone);
        // Churning foam texture — fast scrolling fbm, gated to a band straddling
        // the surface so the white-water clings to the top of the river.
        float bandY = smoothstep(0.16, 0.0, abs(uv.y - waterY));   // surface band
        float churn = rcFbm(vec2(uv.x * 8.0 - tFoam * 0.6, uv.y * 10.0 + tFoam * 0.4));
        float churn2 = rcFbm(vec2(uv.x * 16.0 + 5.0 + tFoam * 0.9, uv.y * 18.0));
        float foamTex = smoothstep(0.45, 0.95, churn * 0.65 + churn2 * 0.5);
        // Mask to the left of the advancing edge; brightest right at the edge.
        // A crisp leading edge reads as a moving wave WALL, not a static blob.
        float behind = smoothstep(foamEdge + 0.03, foamEdge - 0.14, uv.x);
        float edgeGlow = smoothstep(0.045 * GW_GLOW, 0.0, abs(uv.x - foamEdge));
        float foam = inWater * bandY * (foamTex * behind + edgeGlow * 1.1);
        // The whole foam field brightens on the surge (more violent at impact).
        float violence = 0.40 + 0.60 * surge;
        // GW_DENSITY: scale the foam coverage/alpha so the water reads as lusher
        // white-water (>1) or sparser / more open 留白 (<1). 1.0 = authored.
        vec3 foamCol = vec3(0.78, 0.92, 1.00);     // brilliant white-cyan #d8f4ff
        effect += foamCol * foam * violence * 0.70 * GW_DENSITY;

        // Deep teal river glow just under the foam — anchors the water plane
        // without lifting the center. Confined to the lower-left water region,
        // fading away from the active foam.
        float teal = inWater * smoothstep(0.30, 0.0, abs(uv.y - (waterY - 0.10)))
                   * smoothstep(faceX + 0.02, 0.10, uv.x);
        vec3 riverCol = vec3(0.04, 0.20, 0.26);    // deep teal #0a2630-ish
        effect += riverCol * teal * (0.20 + 0.18 * surge);
    }

    // ---- bright impact flare on the rock face at the moment of the slam ----
    // A vertical bright bloom hugging the cliff face, low on the rock where the
    // breaker hits, flashing with the surge. This is the kinetic core.
    {
        float hit = surge * surge;                            // sharpens flash
        // GW_GLOW widens the impact bloom hugging the face (dreamier when high).
        float faceBand = smoothstep(0.05 * GW_GLOW, 0.0, distFace);  // hug the face
        // Vertical extent: concentrated near the waterline, tapering up the rock.
        float vband = smoothstep(0.10, 0.0, max(0.0, uv.y - (waterY + 0.02)))
                    * smoothstep(-0.10, 0.04, uv.y - (waterY - 0.14));
        float flare = faceBand * vband * hit;
        vec3 flareCol = vec3(0.82, 0.94, 1.00);
        effect += flareCol * flare * 0.85;
    }

    // ============================================================
    // 捲起千堆雪 : radial spray burst — launches UP the rock, falls DOWN
    // ============================================================
    // On each strike, a fan of spray particles erupts from the impact point at
    // the cliff base and arcs up the rock face under gravity. Particle vertical
    // position is a ballistic arc keyed to the pulse phase: it rises while the
    // surge builds and rains back down as the surge releases. Particles are
    // additive cyan-white motes — "a thousand drifts of snow".
    //
    // GATE: the whole plume is anchored at the cliff base and fans UP-and-LEFT
    // over a bounded reach (~0.4 in aspected x, rising ~0.25 in y above the
    // waterline, never below it). A cheap aspected bounding box around that
    // reach lets the entire NSPRAY loop AND the base sheet be skipped for every
    // pixel outside the plume — i.e. the upper sky, the center, the far-left
    // water, and everything to the right of the cliff. Inside the box, each
    // individual mote glow already falls to ~0 outside its own radius, so the
    // box only adds the cliff-base neighbourhood, preserving the look exactly.
    {
        // Impact origin: where the foam edge meets the water at the cliff base.
        vec2 origin = vec2((faceX - 0.01) * aspect, waterY + 0.01);

        // Cheap plume bounding box in aspected space. Motes launch up-left from
        // the origin (cos(ang) in [cos(2.70),cos(1.45)] ~ [-0.90, 0.12], i.e.
        // mostly leftward; sin(ang) > 0 i.e. upward) and gravity pulls them back
        // to the waterline. Generous margins so no visible mote is clipped.
        vec2 d = ap - origin;
        bool inPlume = d.x > -0.46 && d.x < 0.12
                    && d.y > -0.05 && d.y < 0.30;
        if (inPlume) {
            // Spray only meaningful once the surge is building; intensity peaks at slam.
            float spawn = smoothstep(0.18, 0.62, ph);             // particles appear
            // Local "launch time" since spawn began — drives the ballistic arc.
            // 0 at spawn, growing through the rest of the pulse so motes rise then fall.
            float lt = clamp((ph - 0.20) / 0.78, 0.0, 1.0);       // 0..1 flight time

            const int NSPRAY = 26;
            float burst = 0.0;
            // Per-particle flight time and turbulence wobble are shared.
            float seedp = floor(iTime / STRIKE);                  // which strike
            float t = lt * 1.15;                                  // local flight time
            // Turbulence wobble: original used sin(theta + fi) per particle.
            // Hoist theta = mod(iTime,11)*3 out of the loop; expand the angle
            // sum so only cos(fi)/sin(fi) vary per iteration (identical result).
            float wobC = cos(mod(iTime, 11.0) * 3.0);
            float wobS = sin(mod(iTime, 11.0) * 3.0);
            for (int i = 0; i < NSPRAY; i++) {
                float fi = float(i);
                // Per-particle randoms (stable across frames within a pulse; the
                // pulse index reseeds so successive strikes differ).
                float r1 = rcHash(vec2(fi * 1.37, seedp * 0.911 + 4.0));
                float r2 = rcHash(vec2(fi * 2.71 + 9.0, seedp * 0.533));
                float r3 = rcHash(vec2(fi * 0.53 + 3.0, seedp * 1.711 + 1.0));

                // Launch angle: fanned UP-and-LEFT off the rock (spray peels back
                // from the vertical face out over the water). Mostly steeply upward
                // so the plume climbs the rock face (捲起千堆雪).
                float ang = mix(2.70, 1.45, r1);                  // radians (up-left fan)
                float speed = mix(0.24, 0.50, r2);                // initial speed
                float g = 0.55;                                   // gravity

                // Ballistic offset in aspected space. Vertical (y) uses uv.y where
                // LARGER y = HIGHER on screen, so launch ADDS to y (up) and gravity
                // SUBTRACTS (down) — correct upright direction.
                float vx = cos(ang) * speed;                      // horizontal (mostly -)
                float vy = sin(ang) * speed;                      // vertical (+ = up)
                vec2 off = vec2(vx * t, vy * t - 0.5 * g * t * t);
                // A little turbulence wobble so motes don't fly on perfect parabolas.
                // sin(theta + fi) = sin(theta)cos(fi) + cos(theta)sin(fi)
                // GW_ENERGY scales the wobble AMPLITUDE (eAmp), with extra chop
                // above default (eGust) — motes scatter more wildly when lively.
                off.x += 0.02 * (wobS * cos(fi) + wobC * sin(fi)) * t * (eAmp + 0.6 * eGust);

                vec2 ppos = origin + off;
                // Skip the glow for motes whose centre is well outside this pixel —
                // the exp() glow is already ~0 beyond a few radii, so this only
                // drops invisible contributions.
                vec2 md = ap - ppos;
                // Skip radius widens with GW_GLOW so the softer, larger motes are
                // not hard-clipped; at the default (GW_GLOW=1) it is exactly 0.0025.
                if (dot(md, md) > 0.0025 * GW_GLOW * GW_GLOW) continue;   // > ~0.05 away
                // Particle fades in at spawn, fades as it ages / falls past origin.
                float life = spawn * smoothstep(1.05, 0.4, lt);
                // Stop drawing a mote once it has fallen back below the waterline.
                float aliveAbove = smoothstep(-0.03, 0.02, ppos.y - (waterY - 0.02));
                // GW_GLOW softens / enlarges each mote (the r fed to rcGlow's exp).
                float sz = mix(0.006, 0.014, r3) * GW_GLOW;
                float mote = rcGlow(ap, ppos, sz);
                burst += mote * life * aliveAbove * (0.6 + 0.5 * r2);
            }
            // A soft sheet of spray at the base under all the motes — the bulk plume.
            // GW_GLOW widens the sheet's soft radius for a dreamier bloom.
            float sheet = surge * smoothstep(0.12 * GW_GLOW, 0.0, length((ap - origin) * vec2(1.0, 1.3)))
                        * smoothstep(-0.02, 0.05, uv.y - (waterY - 0.02));

            // GW_DENSITY scales the spray coverage too — more heaped "snow" off
            // the rock when lush, a thinner plume when sparse. 1.0 = authored.
            vec3 sprayCol = vec3(0.85, 0.95, 1.00);    // white-cyan snow #d8f4ff
            effect += sprayCol * burst * 0.85 * GW_DENSITY;
            effect += sprayCol * sheet * 0.55 * GW_DENSITY;
        }
    }

    // ---- faint cold mist drifting low over the open water (atmosphere) ----
    // Very dim, lower-left only, well away from the text center. Adds depth.
    //
    // GATE: `lowLeft` is the product of two smoothsteps that vanish above
    // uv.y~0.34 and right of uv.x~0.62. Outside that lower-left wedge the mist
    // contributes nothing — skip its fbm there.
    {
        float lowLeft = smoothstep(0.34, 0.10, uv.y) * smoothstep(0.62, 0.0, uv.x);
        if (lowLeft > 0.0) {
            float mist = rcFbm(vec2(uv.x * 3.0 + tDrift * 0.04, uv.y * 4.0 + 2.0));
            mist = smoothstep(0.55, 0.95, mist);
            effect += vec3(0.16, 0.26, 0.32) * mist * lowLeft * 0.05;
        }
    }

    // ---- MANDATORY composite : additive, luminous-on-dark, text legible ----
    effect = max(effect, vec3(0.0));

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (cliff rim, foam, the
    // spray and mist alike) so the feeling reads at a glance — cold/bleak (-1)
    // through the authored cyan-white (0) to warm/tender (+1). Default 0 = identity.
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;
    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}