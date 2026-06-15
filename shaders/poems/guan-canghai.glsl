// 觀滄海 (Guān Cānghǎi) — Gazing at the Vast Sea — 曹操 (Cáo Cāo), Han 樂府
//   山島竦峙 ... 秋風蕭瑟，洪波湧起。日月之行，若出其中；星漢燦爛，若出其裏。
//   "Towering the peaks and isles stand ... The autumn wind sighs and moans,
//    mighty billows surge and rise. The sun and moon in their courses seem to
//    issue from within this sea; the brilliant River of Stars, from within it too."
//
// One viewer high on a 碣石山 summit looking DOWN onto the open sea, through a
// full day↔night wheel that loops seamlessly. From back to front, top to bottom:
//   - Sky (a THIN strip across the very top, uv.y≳0.70): heavy 留白, kept dark
//     and open for terminal text. A single luminous celestial disc arcs LOW
//     through that strip — the SUN by day and the MOON by night, mutually
//     exclusive, counter-travelling on a yin-yang wheel (sun left→right, moon
//     right→left) and peaking around uv.y≈0.90 (it never climbs off the top).
//     When the moon is high a sparse, faint 星漢 (River of Stars) twinkles in
//     the top strip and fades out by dawn.
//   - Sea (the DOMINANT band — the high horizon at uv.y≈0.70 down to the near
//     ridge — filling most of the frame and read as seen from above): a deep
//     ocean BLUE, summed low-frequency swell relief scrolling DOWN toward the
//     viewer (洪波湧起 — crests advance to the BOTTOM as iTime increases). A
//     specular GLITTER PATH (灩灩 sun/moon road) shimmers on the water beneath
//     the body's x-position, in the body's colour; with the tall sea it runs a
//     long dramatic reflection column when the body is low (灩灩隨波).
//   - Foreground peaks (a NEAR range across the BOTTOM, uv.y 0 → ~0.22 with
//     jagged summits poking up to ~0.30–0.34): REAL towering peaks built from
//     RIDGED noise (山島竦峙) — sharp summits and V-valleys, not smooth swoops —
//     that you stand among and gaze OVER toward the sea beyond, so they occlude
//     the lowest sea. THREE receding layers give depth: the nearest is darkest,
//     biggest, jaggiest and lowest-rooted; farther layers are smaller, hazier
//     and lighter (atmospheric perspective). Each catches the light only on its
//     ridge tops and the slope facing the body. Summits stay below uv.y≈0.45
//     everywhere (mostly far lower) so the high horizon and text stay clear.
//
// 日月之行 — ONE slow master cycle drives EVERYTHING. From the active body's
// altitude a single light state is derived (warm-gold by day, cool-silver by
// night, dim red-orange at the horizon) and applied coherently to the horizon
// glow, the sea/glitter, and the mountain rim — so the whole frame warms at
// noon, silvers at night, reddens and darkens to almost-black at twilight.
//
// Palette: deep ocean blue sea #07203f → #14529c, sun-gold #ffd39a/#ffb060,
//          moon-silver #d6e4ff, dawn/dusk #e08a4e, near-black ridge #04080b.
//
// Four "feeling" dials tune the scene (neutral defaults reproduce this look):
//   GW_MOOD   warm/cool global tone · GW_ENERGY  autumn-wind swell agitation
//   GW_DENSITY horizon-glow + glitter + star fill vs 留白 · GW_GLOW  disc/glow/rim bloom.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls. In this day/night scene:
//   MOOD   — global warm/cool tone over sky, disc, sea, glitter and ridge alike.
//   ENERGY — swell agitation: the autumn-wind gust amplitude (and extra
//            choppiness above default), NOT the roll rate (no teleporting waves).
//   DENSITY— how much light fills the void: horizon-glow strength + glitter-path
//            coverage + 星漢 star count, vs heavier 留白 of bare dark sea & sky.
//   GLOW   — bloom/softness of the sun/moon disc, the horizon glow and the
//            mountain rim light.
#ifndef GW_MOOD
#define GW_MOOD 0.0      // palette warmth: -1 cold/blue .. 0 neutral .. +1 warm
#endif
#ifndef GW_ENERGY
#define GW_ENERGY 1.0    // motion: 0.3 still/glassy .. 1 .. 2 stormy
#endif
#ifndef GW_DENSITY
#define GW_DENSITY 1.0   // fill vs 留白: 0.3 sparse/empty .. 1 .. 1.8 luminous
#endif
#ifndef GW_GLOW
#define GW_GLOW 1.0      // bloom/softness: 0.6 crisp .. 1 .. 2.5 dreamy
#endif

// --- hash / value-noise / fbm (house style; defined before use) ---

float gcHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float gcNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = gcHash(i);
    float b = gcHash(i + vec2(1.0, 0.0));
    float c = gcHash(i + vec2(0.0, 1.0));
    float d = gcHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float gcFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * gcNoise(p); p *= 2.04; a *= 0.5; }
    return v;
}

// Swell height field at a sea-plane position. `sp` is the perspective sea
// coordinate (sp.x across, sp.y = distance from horizon, increasing toward
// the viewer). `t` is a seamless looping clock. Returns a signed height in
// roughly [-1, 1]: the summed low-frequency swell bands plus a slow fbm
// roughness, all scrolling toward the viewer (sp.y increasing over time → the
// same crest sits at larger sp.y later → it moves toward the bottom).
float swellHeight(vec2 sp, float t) {
    // 洪波湧起 — the DOMINANT surge rolls toward the viewer (in +sp.y → crests
    // advance to the bottom as t grows). Two near-aligned toward-viewer bands
    // carry most of the weight so the advancing roll always reads.
    float h = 0.0;
    h += 0.52 * sin(sp.y *  6.0 + sp.x * 0.7  - t * 0.90);
    h += 0.28 * sin(sp.y *  9.5 - sp.x * 1.1  - t * 1.30 + 1.7);

    // Cross-directional swell so the surface INTERFERES — crests curve, pinch
    // and break up instead of marching as parallel horizontal stripes. Each
    // travels a different way on its own incommensurate wavelength/phase/speed,
    // and all are weighted UNDER the toward-viewer surge above so the advancing
    // roll still dominates. To actually BEND the horizontal crests these carry a
    // strong sp.x dependence (they shear the bands sideways), not just ride them.
    //   · lateral — runs mostly along +sp.x (crests slide / bow sideways)
    h += 0.26 * sin(sp.x *  5.3 + sp.y * 1.6  - t * 0.62 + 0.8);
    //   · diagonal — a steep sp.x slant against a gentle sp.y so crests tilt/shear
    h += 0.21 * sin(sp.x *  4.4 + sp.y * 3.0  - t * 1.07 + 2.4);
    //   · a counter-propagating set drifting toward the horizon (−sp.y) with a
    //     strong lateral component: meets the surge and pinches the crests off.
    h += 0.15 * sin(sp.x *  3.6 - sp.y * 8.1  + t * 0.74 + 5.1);

    // Slow large-scale fbm roughness travelling with the swell so the crest
    // lines aren't perfectly straight — the sea breathes as one rough body.
    float rough = gcFbm(vec2(sp.x * 1.3, sp.y * 2.2 - t * 0.35)) - 0.5;
    h += rough * 0.42;
    // Normalize by the summed band weight so the field stays within ~[-1,1].
    // (0.52+0.28+0.26+0.21+0.15 = 1.42 of sines, plus ±0.21 of roughness ⇒
    //  worst-case |h|≈1.63 → ×0.42 ≈ 0.68, comfortably inside [-1,1].)
    return h * 0.42;
}

// One range's silhouette height in uv.y at horizontal position `x` (use uv.x),
// built from RIDGED noise so the profile is SHARP towering peaks and V-valleys
// (山島竦峙), not smooth swoops. Ridged value noise = 1 - |2·noise - 1|, which
// folds the smooth field at every zero crossing into hard creases — layering a
// few octaves at rising frequency / falling amplitude stacks sharp sub-peaks on
// the big ones. `freq` sets the peak spacing (jaggedness), `phase` shifts the
// profile so the three layers never coincide, `base` is the range's root floor
// (where its body fills up from the bottom) and `amp` its peak relief.
float ridgeLine(float x, float freq, float phase, float base, float amp) {
    float v = 0.0, a = 0.5, p = x * freq + phase;
    // Layered ridged noise: each octave's sharp crease rides on the last.
    for (int i = 0; i < 4; i++) {
        float n = gcNoise(vec2(p, phase * 0.7 + float(i) * 1.3));
        float r = 1.0 - abs(2.0 * n - 1.0);   // ridged fold → sharp peak / V-valley
        r = r * r;                            // sharpen the creases further
        v += a * r;
        a *= 0.5; p *= 2.07;
    }
    // v ∈ ~[0,1] with a jagged silhouette; lift it onto the range's root floor.
    return base + amp * v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                 // host is top-origin: uv.y = 1 at top

    // Sample the terminal glyph layer with the UNFLIPPED coord.
    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    // Aspect-correct so swell wavelengths read evenly across any window shape.
    float aspect = iResolution.x / iResolution.y;
    float ax = (uv.x - 0.5) * aspect;  // centered, aspect-corrected x

    // Seamless looping clocks. Never feed raw iTime to fast oscillators.
    float tRoll = mod(iTime, 62.831853);   // swell roll (≈ 10 wave periods)
    float tWind = mod(iTime, 120.0);        // slow wind-envelope gusting
    float tStar = mod(iTime, 40.0);         // star twinkle
    float tGlit = mod(iTime, 50.0);         // 灩灩 sparkle clock (½·CYCLE: loops clean)

    // ---- 日月之行 : the one master day↔night wheel --------------------------
    // θ wraps continuously at the loop seam: tc∈[0,CYCLE) → th∈[0,2π).
    float CYCLE = 100.0;
    float tc = mod(iTime, CYCLE);
    float th = tc * (6.2831853 / CYCLE);

    // Sun & moon altitudes are mutually exclusive: sun up for θ∈(0,π), moon up
    // for θ∈(π,2π). The active body is whichever is above the horizon.
    float sunAlt  = sin(th);
    float moonAlt = -sin(th);
    float isDay   = step(0.0, sunAlt);          // 1 sun-side of the wheel
    float night   = 1.0 - isDay;
    float lightAlt = max(sunAlt, moonAlt);      // active body altitude [0..1]
    // Smooth day↔night factor (eases through twilight) for tone blends that must
    // not SNAP at the horizon crossing — the sea state and the mountain hue.
    // 0 deep night · 1 full day.
    float dayAmt  = smoothstep(-0.12, 0.22, sunAlt);

    float horizon = 0.70;                        // HIGH horizon: sea below fills
                                                 // most of the frame (seen from
                                                 // above), thin dark sky above.
    float arc = 0.20;                            // low arc → disc peaks ≈uv.y 0.90

    // Shared right-biased arc x-position (honours the right rule: peak sits
    // right of centre). The sun sweeps left→right across the day; the moon,
    // evaluated at its own half of the wheel, counter-travels right→left — a
    // yin-yang wheel. bodyX is in aspect-corrected x (matches `ax`).
    float bodyX = 0.58 - 0.34 * cos(th);
    // Disc rises FROM the sea horizon to a peak and sinks back into it.
    float bodyY = horizon + arc * max(lightAlt, 0.0);

    // ---- ONE light state, derived from the active body --------------------
    vec3 dayCol  = vec3(1.000, 0.827, 0.604);    // warm gold  #ffd39a
    vec3 nightCol= vec3(0.839, 0.894, 1.000);    // cool silver #d6e4ff
    vec3 duskCol = vec3(0.878, 0.541, 0.306);    // dawn/dusk red-orange #e08a4e
    // Day/night base tone, then pushed toward dusk-red as the body nears the
    // horizon (low lightAlt) — twilight is the reddest, dimmest moment.
    vec3 baseCol = mix(nightCol, dayCol, isDay);
    float lowness = 1.0 - smoothstep(0.0, 0.34, lightAlt);   // 1 at horizon
    vec3 lightCol = mix(baseCol, duskCol, lowness);
    // Global light intensity: ignites as the body clears the horizon, dim near
    // it (twilight darkest), full at altitude.
    float lightI = smoothstep(0.0, 0.30, lightAlt);

    // Day/night CAST-light asymmetry. The moon reflects far less light than the
    // sun, so the world it lights must go QUIET, cool and dark — night is not a
    // second day. `bodyLight` scales every bit of ENVIRONMENTAL light the active
    // body throws onto the world (horizon glow, sea glitter/sparkle, swell-relief
    // tint, mountain rim/slope): full by day, ~MOON_LIGHT by night. It is NOT
    // applied to the disc core itself — the moon DISC stays a bright silver point
    // (see the disc block), so the asymmetry is purely in reflected/cast light.
    float MOON_LIGHT = 0.45;
    float bodyLight = mix(MOON_LIGHT, 1.0, isDay);

    vec3 effect = vec3(0.0);

    // 秋風蕭瑟 : a slow global wind-envelope that swells and eases the whole
    // sea's amplitude — the autumn wind gusting. Long seamless cycle, gentle.
    // GW_ENERGY scales the gust DEPTH (agitation amplitude) about its mean, not
    // the gust RATE — glassy-calm <-> stormy rather than the swell speeding up.
    float eAmp = 0.45 + 0.55 * GW_ENERGY;                          // 1.0 at default
    float wind = 0.78 + 0.22 * eAmp * sin(tWind * (6.2831853 / 120.0));

    // ---- foreground peaks (山島竦峙): a near ridged-noise range across the bottom --
    // THREE receding ridged-noise ranges read as real towering peaks one stands
    // AMONG and gazes OVER. They sit as a near foreground band along the BOTTOM
    // (rooted at uv.y≈0, jagged summits poking up to ~0.30–0.34), so they occlude
    // the lowest sea while the high horizon and text stay clear above. Ordered by
    // DEPTH (drawn near-on-top, so the near mass occludes the ranges behind):
    //   NEAR — closest: biggest, jaggiest (highest freq detail), darkest, rooted
    //          LOWEST; its summits reach highest (~0.30–0.34).
    //   MID  — a middle range: smaller peaks, hazier, rooted a touch higher so a
    //          band of it shows above the near valleys.
    //   FAR  — the receding range: smallest peaks, haziest/lightest (atmospheric
    //          perspective), peeking above the others between near summits.
    // Summits stay below uv.y≈0.45 everywhere (mostly far lower) so the open sea
    // dominates and the top strip stays free for glyphs.
    float ridgeNear = ridgeLine(uv.x, 6.5,  4.0, 0.000, 0.340);  // biggest, jaggiest, lowest root
    float ridgeMid  = ridgeLine(uv.x, 9.0, 13.0, 0.045, 0.215);  // middle range
    float ridgeFar  = ridgeLine(uv.x, 12.5, 23.0, 0.080, 0.150); // far range, smallest peaks
    // The overall silhouette edge is the union (whichever range is tallest here).
    float ridgeY = max(max(ridgeFar, ridgeMid), ridgeNear);
    float ridgeMask = step(uv.y, ridgeY);                  // 1 inside the mountains

    float sea = 0.0;
    if (ridgeMask < 0.5) {
        // ---- sea : horizon down to the ridgeline ----
        float seam = 0.02 * GW_GLOW;
        sea = smoothstep(horizon + seam, horizon - seam, uv.y);  // 1 in water
    }

    if (sea > 0.0) {
        // Perspective sea coordinate. depth = 0 at horizon, grows toward the
        // viewer (bottom). Compresses near the horizon, expands near the
        // viewer, so swell wavelength lengthens as the water approaches.
        float below = clamp((horizon - uv.y) / horizon, 0.0, 1.0);
        float depth = pow(max(below, 1e-4), 0.62);   // 0 (far) .. ~1 (near)

        // Sea coordinate fed to the swell field. The x term spreads with depth
        // so crests fan slightly toward the viewer (perspective convergence).
        vec2 sp = vec2(ax * (0.6 + 0.8 * depth), depth * 3.2);

        // Height and its along-depth slope (finite difference) → the surface
        // tilt that decides which faces catch the light.
        float h  = swellHeight(sp, tRoll) * wind;
        float h2 = swellHeight(sp + vec2(0.0, 0.06), tRoll) * wind;
        float slope = (h2 - h) / 0.06;     // d(height)/d(depth toward viewer)

        // Base water: deep ocean NAVY at the far horizon easing to a mid
        // ocean-blue near the viewer — bluer than the old teal (more blue
        // channel, less green), kept dark in the body so white text reads;
        // brightness is concentrated in the glitter path, crest-silver and
        // horizon glow, not the flat water.
        vec3 deep = vec3(0.027, 0.125, 0.247);   // #07203f deep ocean navy
        vec3 near = vec3(0.078, 0.322, 0.612);   // #14529c mid ocean-blue
        vec3 water = mix(deep, near, depth);
        // Day↔night sea STATE — the clearest signal that the wheel has turned.
        // By DAY the sea is a luminous ocean blue reflecting the blue sky: lifted
        // a touch brighter and bluer. By NIGHT it sinks much darker, cooler and
        // quieter (little moonlight) — so day-sea and night-sea read as clearly
        // different water, not one plane under different glints. Eased through
        // twilight by dayAmt so the tone never snaps at the horizon crossing.
        vec3 dayWater   = water * vec3(1.05, 1.10, 1.16);   // brighter, bluer by day
        vec3 nightWater = water * vec3(0.26, 0.34, 0.46);   // deep dark navy by night
        water = mix(nightWater, dayWater, dayAmt);
        // Blue sky-reflection grazing the day sea near the horizon (atmospheric),
        // which also holds the sea↔sky tonal step: pale-bright sky over a deeper,
        // more saturated blue sea, the bright waterline seam between the two.
        vec3 skyReflect = vec3(0.24, 0.45, 0.80);
        float reflW = dayAmt * (1.0 - smoothstep(0.0, 0.45, depth)) * 0.30;
        water = mix(water, skyReflect, reflW);

        // Fine high-frequency CHOP riding on the big swells: a couple of fast
        // fbm octaves at small scale, scrolling toward the viewer on tRoll, so
        // the surface is textured rather than smooth/banded. Stronger near the
        // viewer (where detail is visible), vanishing at the horizon. Adds a
        // small signed wrinkle on top of the swell height the shading reads.
        float chop = gcFbm(vec2(sp.x * 6.5, sp.y * 7.5 - tRoll * 0.9)) - 0.5;
        chop += 0.5 * (gcFbm(vec2(sp.x * 13.0 + 4.0, sp.y * 14.0 - tRoll * 1.4)) - 0.5);
        chop *= (0.25 + 0.55 * depth) * wind;    // fade out toward the horizon
        float hT = h + chop * 0.38;              // textured surface height

        // Swell shading: crest faces lifted, troughs sink darker, so the whole
        // plane reads as rolling relief. Contrast strengthens toward the viewer
        // and rides the wind gust. The fine chop wrinkles the relief so the
        // water reads as a textured sea, not flat bands.
        float relief = 0.5 + 0.5 * hT;           // 0 trough .. 1 crest
        float reliefGain = (0.42 + 0.55 * depth) * wind
                         * (1.0 + 0.45 * max(GW_ENERGY - 1.0, 0.0) * depth);
        water *= 0.50 + reliefGain * relief;

        // Light the sea by the active body: the whole surface takes the body's
        // colour, brightest where the swell crests face up. Dim by night, broad
        // and warm by day, red at twilight. bodyLight drops the moon's swell
        // tint to ~45% so the night sea relief stays dark and cool.
        vec3 seaLit = lightCol * (0.5 + 0.5 * relief) * lightI * bodyLight;
        water += seaLit * (0.10 + 0.10 * depth);

        // 灩灩 glitter path : a shimmering near-vertical reflection column on
        // the water directly beneath the body's x-position, in the body's
        // colour. Longest/brightest when the body is LOW near the horizon, and
        // it reaches further down the water then (the sun/moon road).
        float dxg = ax - bodyX;
        // Horizontal: a soft column, slightly widened by glitter sparkle.
        float spark = 0.6 + 0.4 * sin(sp.x * 9.0 - tRoll * 1.7 + sp.y * 4.0);
        float colW = exp(-dxg * dxg * 70.0);             // tight bright column
        // Vertical reach: with the tall sea the road has room to run LONG and
        // dramatic (灩灩隨波) when the body is low — it spans nearly the whole
        // water then; short and tight when the body rides high.
        float reach = mix(0.30, 1.35, lowness);
        float vfall = smoothstep(reach, 0.0, depth);     // fades with distance down
        // Crests inside the column flash; only viewer-facing rises catch it.
        float facing = smoothstep(0.0, -1.4, slope);
        float crest = smoothstep(0.45, 0.95, relief);
        // Low body → the road brightens and broadens for a more dramatic column.
        float drama = 1.0 + 0.6 * lowness;
        float glitter = colW * (0.35 + 0.65 * crest * facing) * spark * vfall * drama;
        // Strength tracks the light; GW_DENSITY scales coverage; GW_GLOW blooms.
        // bodyLight dims the moon road to ~45% — but against the now near-black
        // night water it still reads as a clean silver sun/moon road, just no
        // longer a bright fill across the whole sea.
        water += lightCol * glitter * lightI * bodyLight * 0.9 * GW_DENSITY * (0.7 + 0.3 * GW_GLOW);

        // 灩灩 glitter SPARKLE : sparse hashed high-frequency glints flashing on
        // the crest faces where the light hits the water — small bright points,
        // not a wash. A fine cell grid over the sea coord; only a few percent of
        // cells host a glint, each twinkling on the looping tGlit clock. Confined
        // to where the body's light actually falls and to the NEAR/lower water:
        //   · sparkLight — a BROAD column under the body (wider than the tight
        //     reflection road) so glints only appear on the lit side, never on
        //     the central/off-body flat water (keeps the text field dark).
        //   · depth weight — brightest under the body and on the near (lower)
        //     water, fading to nothing toward the horizon strip.
        // Tied to GW_DENSITY (sparser when DENSITY is low). Concentrated on
        // crest faces, so the open mid water and the top strip stay dark/open.
        float sparkLight = exp(-dxg * dxg * 6.0);            // broad lit side only
        float sparkNear  = smoothstep(0.30, 0.95, depth);    // near/lower water only
        vec2  sg  = vec2(sp.x * 26.0, sp.y * 30.0 - tGlit * 0.6);
        vec2  sgi = floor(sg);
        vec2  sgf = fract(sg) - 0.5;
        float sh  = gcHash(sgi);
        // Only the rarest cells host a glint (× GW_DENSITY) — keep it sparse.
        float on  = step(1.0 - 0.07 * GW_DENSITY, sh);
        float pt  = exp(-dot(sgf, sgf) * 26.0);              // tight glint point
        // Per-glint twinkle on the looping clock (phase scattered by the hash).
        float gtw = 0.5 + 0.5 * sin(tGlit * (6.2831853 / 50.0) * (5.0 + 7.0 * sh)
                                    + sh * 41.0);
        float glints = on * pt * gtw * crest * facing
                     * sparkLight * sparkNear;
        water += lightCol * glints * lightI * bodyLight * 1.1 * GW_DENSITY;

        // Cool whitecap flecks — VERY sparse and dim, only on the highest near
        // crests (洪波 breaking). Rare hashed points; cool-white, kept faint so
        // they read as flecks, never a band, and only on the near water.
        float capTop  = smoothstep(0.82, 0.97, relief);      // only the highest crests
        float capNear = smoothstep(0.55, 1.0, depth);        // near water only
        vec2  cg  = floor(vec2(sp.x * 18.0, sp.y * 20.0 - tGlit * 0.4));
        float ch  = gcHash(cg + 19.3);
        float cap = step(0.985, ch) * capTop * capNear * facing;   // very rare
        water += vec3(0.72, 0.80, 0.92) * cap * 0.10 * lightI;

        effect += water * sea;
    }

    // ---- 日 daytime sky : atmospheric luminance that exists ONLY by day -----
    // The night sky stays a dark 留白 void (the moon casts little light); but by
    // day the air itself should glow so the scene reads as daytime, not a lit
    // disc over a black sky. This band lives ONLY on the sun side of the wheel
    // and ONLY in the sky strip above the horizon, and is shaped for text:
    //   · dayFill gates it to day — smoothstep on sunAlt (negative at night ⇒ 0),
    //     so it ignites as the sun clears the sea and fades back out through dusk;
    //     the NIGHT sky (dimmed moon-cast) is never touched.
    //   · BRIGHTEST just above the horizon and on the SUN'S side (right), easing
    //     DOWN to dark at the very TOP edge and toward the TOP-LEFT — so the
    //     luminous band hugs the horizon/sun while 留白 (dark) is preserved at the
    //     top-left where terminal glyphs start (and the right-bias rule is kept).
    //   · COLOUR a believable warm day sky: pale warm/gold near the sun & horizon
    //     easing to a cool pale blue away from the sun and up — a soft gradient.
    //   · Tied to GW_DENSITY like the other sky light.
    float dayFill = smoothstep(0.0, 0.32, sunAlt);          // 1 by day · 0 at night
    if (dayFill > 0.0 && uv.y > horizon - 0.02) {
        // Vertical: brightest at the horizon, easing to dark at the top edge so
        // the very top stays open. Soft exponential band into the sky.
        float aboveH = max(uv.y - horizon, 0.0);
        float skyV   = exp(-aboveH * 7.5);                  // 1 at horizon → dark up top
        // Extra darkening pull right at the very top edge (text headroom).
        skyV *= smoothstep(1.0, 0.80, uv.y);
        // Horizontal: a broad warm lobe centred on the sun (right), with a low
        // ambient floor that is LOWEST at the left so the top-left stays darkest.
        float dxs   = ax - bodyX;
        float sunLobe = exp(-dxs * dxs * 0.9);              // broad glow around the sun
        // Left↔right ambient ramp: ~0.18 at far left rising to ~0.6 at far right,
        // so even away from the sun the right reads brighter than the left.
        float lr     = 0.18 + 0.42 * smoothstep(-0.9, 0.9, ax);
        // The sun's brightening of the sky is kept MODEST so its hue no longer
        // over-shines the blue (was a hot blob hugging the disc).
        float skyH   = clamp(lr + 0.32 * sunLobe, 0.0, 1.1);
        float skyAmt = skyV * skyH;
        // Colour: a believable BLUE day sky across almost the whole strip, warming
        // to pale gold ONLY in a TIGHT lobe right at the sun (steep falloff, and
        // only low near the horizon) — so the sky reads blue, with just a warm
        // halo hugging the disc instead of a gold wash over everything.
        vec3 skyBlue = vec3(0.36, 0.56, 0.88);             // daytime sky blue
        vec3 skyWarm = vec3(0.96, 0.86, 0.64);             // pale gold, sun core only
        float warmth = exp(-dxs * dxs * 5.0)               // tight: only at the sun
                     * (1.0 - smoothstep(0.0, 0.10, aboveH)); // and only low by the horizon
        vec3 skyCol  = mix(skyBlue, skyWarm, clamp(warmth, 0.0, 1.0) * 0.7);
        // Fill amount: enough to read as a daytime sky, tied to GW_DENSITY and
        // gently bloomed with GW_GLOW. Kept a touch lower than before so the blue
        // is present without glaring; the top-left stays markedly darker than the
        // horizon band (skyV·lr is small there).
        effect += skyCol * skyAmt * dayFill * 0.56 * GW_DENSITY * (0.85 + 0.15 * GW_GLOW);
    }

    // ---- 日 horizon haze : a soft separation seam at the waterline (day) -----
    // A faint, soft brighter band sitting RIGHT on the horizon so the waterline
    // reads as a clean edge between the lighter sky above and the bluer sea
    // below — kept soft (Gaussian on distance to the horizon), never a hard line.
    // Softened so it separates without glaring: a WIDER, gentler band at about
    // half its former strength, only mildly sun-biased (so no hot blob under the
    // disc), and a hair cooler so it reads as haze, not a white streak. Pale and
    // right-leaning so it honours the right rule and never lifts the dark
    // top-left. Day-only (gated by dayFill); night renders unchanged.
    if (dayFill > 0.0) {
        float dseam = uv.y - horizon;
        float hazeV = exp(-dseam * dseam * 380.0);           // wider, gentler band
        float hazeH = 0.40 + 0.45 * exp(-(ax - bodyX) * (ax - bodyX) * 0.8);
        vec3  hazeCol = vec3(0.80, 0.83, 0.86);              // pale cool-neutral seam
        effect += hazeCol * hazeV * hazeH * dayFill * 0.06 * GW_DENSITY;
    }

    // ---- 日月之行 horizon glow : light issuing from within the sea ----------
    // A low, wide band hugging the horizon, CENTRED UNDER bodyX so it tracks
    // the body across the frame. Coloured by the active light; scaled by
    // intensity and GW_DENSITY; bloomed by GW_GLOW. Kept low and wide so the
    // central sky stays open for text.
    {
        float dy = uv.y - horizon;
        float vUp   = exp(-max(dy, 0.0)  * (24.0 / GW_GLOW));   // into the sky
        float vDown = exp(-max(-dy, 0.0) * (16.0 / GW_GLOW));   // into the water
        float vband = max(vUp, vDown);
        // Horizontal swell of light centred on the body (tracks it L↔R).
        float dxh = ax - bodyX;
        float hband = exp(-dxh * dxh * (2.6 / GW_GLOW));
        float g = vband * hband;
        // GW_DENSITY scales how much the 日月之行 light fills the void; bodyLight
        // drops the moon's horizon glow to ~45% so night stays dark and open.
        // The DAY band is trimmed (×0.78) to soften the bright waterline without
        // touching the night moon-glow (isDay gates the cut; the glow is ≈0 at the
        // horizon crossing, so there is no snap at the day/night boundary).
        effect += lightCol * g * lightI * bodyLight * 0.34 * (1.0 - 0.22 * isDay) * GW_DENSITY;
    }

    // ---- the sun / moon disc ----------------------------------------------
    // Soft luminous disc (no hard circle) at (bodyX, bodyY), only while the
    // body is above the horizon. Warm gold core easing outward by day; cool
    // silver by night. Ignites via smoothstep(alt) so it lights as it clears
    // the sea and dims as it sets. A wide bloom halo, broadened by GW_GLOW.
    if (lightAlt > 0.0) {
        vec2 dpos = vec2((ax - bodyX), (uv.y - bodyY));
        float d2 = dot(dpos, dpos);
        float ignite = smoothstep(0.0, 0.14, lightAlt);
        // Disc core: tight soft falloff. Halo: wide soft bloom.
        float disc = exp(-d2 * (900.0 / GW_GLOW));
        float halo = exp(-d2 * (90.0  / GW_GLOW));
        // Sun core eases gold→amber outward; moon stays cool silver.
        vec3 sunCore = vec3(1.000, 0.827, 0.604);   // #ffd39a
        vec3 sunEdge = vec3(1.000, 0.690, 0.376);   // #ffb060
        vec3 discCol = mix(mix(sunEdge, sunCore, disc), nightCol, night);
        // Toward the horizon the disc reddens with the rest of the light.
        discCol = mix(discCol, duskCol, lowness * 0.7);
        // The DISC itself is NOT dimmed by bodyLight — it is a self-luminous
        // body, not reflected light, so the moon stays a bright, crisp silver
        // point against the now-darker night sky. The moon gets only a whisper
        // less core gain (0.85) and a slightly tighter bloom than the sun, so it
        // reads as the cooler, smaller disc while remaining clearly luminous.
        float discGain = mix(0.85, 1.05, isDay);     // moon 0.85 · sun 1.05
        float haloGain = mix(0.22, 0.30, isDay);     // moon bloom a touch tighter
        effect += discCol * (disc * discGain + halo * haloGain) * ignite;
    }

    // ---- 星漢燦爛 : the River of Stars, only while the moon rides high ------
    // Sparse, faint, slowly twinkling points in the UPPER sky (above the disc
    // arc, away from the text mid-field). Fade in with night AND altitude;
    // fade out by dawn. Count/brightness scale with GW_DENSITY.
    float starVis = night * smoothstep(0.18, 0.55, lightAlt);
    if (starVis > 0.0 && uv.y > 0.72) {
        // Upper-sky weighting: densest toward the very top, none mid-frame.
        float top = smoothstep(0.72, 0.98, uv.y);
        // Sparse cell grid; one candidate star per cell, jittered.
        vec2 g = uv * vec2(34.0, 22.0);
        vec2 gi = floor(g);
        vec2 gf = fract(g);
        float pick = gcHash(gi);
        // Keep it sparse: only ~16% of cells host a star (× GW_DENSITY).
        float present = step(1.0 - 0.16 * GW_DENSITY, pick);
        // Jittered position within the cell.
        vec2 jt = vec2(gcHash(gi + 3.1), gcHash(gi + 7.7));
        vec2 dd = gf - jt;
        float pt = exp(-dot(dd, dd) * 140.0);          // soft star point
        // Slow per-star twinkle (seamless on tStar).
        float tw = 0.45 + 0.55 * sin(tStar * (6.2831853 / 40.0) * (0.6 + pick) + pick * 31.4);
        // Night is now genuinely dark (the moon casts little light), so the
        // 星漢 can read more strongly without being washed — lifted from 0.06 to
        // 0.10 so the River of Stars is clearly present at deep night.
        effect += nightCol * present * pt * top * tw * starVis * 0.10 * GW_DENSITY;
    }

    // ---- foreground peaks (山島竦峙): per-layer ridge & body-facing slope lit --
    // Each receding range is a near-black 留白 mass; only its ridge TOPS and the
    // slope facing the body glow, coloured by the active light — so peaks warm
    // at midday, silver at night, red at dawn/dusk, near-black at twilight. The
    // pixel belongs to the NEAREST range whose ridge is above it (near drawn on
    // top), and that range's depth sets BOTH its base darkness/haze and its rim
    // strength: the near mass is darkest with the least rim, the far range is
    // hazier (lifted toward the sky tone) with a brighter rim, so the layers
    // separate as receding peaks rather than one flat cutout.
    if (ridgeMask > 0.5) {
        // Resolve which range owns this pixel (the NEAREST whose crest is above
        // it, since near is drawn on top) and pick its crest, base mass tone,
        // body-haze lift and rim weight. Farther ranges are hazier (their mass
        // lifts toward the sky/horizon tone with distance) and carry a brighter
        // rim; the near mass is darkest with the least rim — so the three read
        // as receding bodies, not three coincident lines.
        // Front-to-back occlusion: the NEAREST range whose crest is above this
        // pixel owns it. Test near first — where the near mass covers the pixel
        // it wins outright (the dark shoulders occlude the ranges behind).
        float ridgeOwn;            // the owning range's crest height
        vec3  ridgeBase;           // near-black mass tone (its darkest, deep body)
        vec3  ridgeHaze;           // tone its body lifts toward up near its crest
        float depthRim;            // rim weight (farther = more)
        if (uv.y < ridgeNear) {    // covered by the near mass → NEAR
            ridgeOwn  = ridgeNear;
            ridgeBase = vec3(0.006, 0.013, 0.020);   // darkest: solid foreground occluder
            ridgeHaze = vec3(0.026, 0.044, 0.060);   // its faintly-lit upper body
            depthRim  = 0.50;                         // nearer → least rim
        } else if (uv.y < ridgeMid) {                // above near, under mid → MID
            ridgeOwn  = ridgeMid;
            ridgeBase = vec3(0.020, 0.036, 0.048);   // dark, a touch hazier than near
            ridgeHaze = vec3(0.062, 0.090, 0.112);
            depthRim  = 0.85;
        } else {                                     // only the far range reaches here
            ridgeOwn  = ridgeFar;
            ridgeBase = vec3(0.044, 0.066, 0.086);   // haziest: lifted toward the sky
            ridgeHaze = vec3(0.104, 0.134, 0.162);
            depthRim  = 1.15;                         // farther → most rim
        }
        // Body fill: each mass reads as a SOLID body via atmospheric haze —
        // lifted toward its haze tone just under its own crest and sinking to
        // its deep base lower down — so it's a filled silhouette receding behind
        // the next (far lightest, near near-black), not a wire.
        float depth = ridgeOwn - uv.y;                         // 0 at crest, grows down
        float body = smoothstep(0.20, 0.0, depth);             // 1 at crest, →0 deep
        vec3 ridge = mix(ridgeBase, ridgeHaze, body);
        // 山色 by daylight: the ranges one stands AMONG take a faint vegetal
        // green-grey by DAY (sunlit slopes over the sea), settling back to cool
        // blue-grey rock by NIGHT. A hue shift on an already near-black mass —
        // kept very subtle and very dark, so legibility is untouched. Eased
        // through twilight by dayAmt.
        ridge *= mix(vec3(1.0), vec3(0.86, 1.08, 0.82), dayAmt * 0.6);
        // The light sits on the mass as a SHADED UPPER SLOPE, not a wire: a band
        // fading down from the crest (the sunlit/moonlit face of the range),
        // with a faint sharper crest highlight on top. The lit face is DEEP on
        // the far/hazy range and only a THIN rim on the near mass (faceDepth
        // tracks depthRim), so the near mass stays a near-black silhouette while
        // the receding ranges catch the light — the stacked faces, not glowing
        // outlines, carry the depth.
        float faceDepth = 0.012 + 0.034 * depthRim;            // near thin .. far broad
        float slope = smoothstep(faceDepth, 0.0, depth);       // lit face
        float crest = smoothstep(0.006, 0.0, depth);           // faint crest line
        // Body-facing slope: the side under bodyX catches a little more light,
        // directional but never blowing the sun-side flank to white.
        float facingSlope = exp(-(ax - bodyX) * (ax - bodyX) * 2.2);
        float lit = (slope * 0.7 + crest * 0.30) * depthRim
                  * (0.60 + 0.40 * facingSlope) * lightI * bodyLight;
        // The lit face warms green-gold by day (vegetation catching the sun) and
        // stays cool silver by night — so the rim colour carries the day/night
        // cue too, not just the dark mass tone.
        vec3 ridgeLit = mix(lightCol, lightCol * vec3(0.82, 1.06, 0.70), dayAmt * 0.5);
        ridge += ridgeLit * lit * (0.8 + 0.5 * GW_GLOW) * 0.11;
        // The ranges are OPAQUE foreground: they REPLACE (occlude) whatever sky,
        // sea or horizon-glow sits behind them — assign, don't add — so the
        // bulk stays a near-black silhouette even where the bright horizon glow
        // tracks the body to a corner. (Earlier the additive glow leaked through
        // the sun-side mass and washed it pale.)
        effect = ridge;
    }

    // ---- MANDATORY composite : additive, luminous-on-dark, text legible ----
    effect = max(effect, vec3(0.0));

    // GW_MOOD: a global warm/cool tone over the WHOLE scene so the feeling reads
    // at a glance — cold/bleak (-1) through the authored balance (0) to
    // warm/tender (+1). Default 0 = identity.
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;
    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
