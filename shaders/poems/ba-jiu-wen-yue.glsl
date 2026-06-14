// 把酒問月 (Bǎ Jiǔ Wèn Yuè) — Asking the Moon, Cup in Hand — Li Bai
//   皎如飛鏡臨丹闕，綠煙滅盡清輝發。
//   "Bright as a flying mirror it nears the vermilion gate; the green mist
//    burns away and pure radiance pours forth."
//
// A mirror-bright moon sits top-center with a soft bloom halo. Drifting
// jade-green fog veils the disc itself; on a slow breathing cycle the fog
// thins to near-nothing and — as it clears — the moon's bloom and a faint
// volumetric ray-fan swell to peak brightness (清輝發), then the fog
// re-gathers and dims the disc. Lower screen stays dark and open for text.
//
// Palette: deep blue-black #060a16 ground, faint jade mist #4a6b5a,
//          brilliant cool-white moon #f2f6ff.
//
// Four feeling dials tune the scene (all-default = authored look):
//   GW_MOOD    warm/cool tone over moon, bloom, rays and mist.
//   GW_ENERGY  agitation of the jade mist's lateral wander (calm <-> billowing).
//   GW_DENSITY how lushly the veil fills the disc's latitude vs clears (留白).
//   GW_GLOW    softness of the moon's bloom halo and ray-fan radii.

#ifndef GW_POEM_INTENSITY
#define GW_POEM_INTENSITY 1.0
#endif

// --- adjustable "feeling" dials -------------------------------------------
// Baked per-scene by `apply` (env vars) and the gallery sliders; the #ifndef
// defaults here are the NEUTRAL baseline — all-default reproduces the scene's
// authored look. Every poem reads the same four dials so the whole collection
// is tunable from one set of controls. Here: GW_MOOD warms/cools the whole
// moonlit scene, GW_ENERGY agitates the drifting jade mist's wander, GW_DENSITY
// thickens vs thins the veil (留白 below the disc), GW_GLOW softens the moon's
// bloom halo and ray-fan.
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

// ---- hash / value-noise / fbm (inlined, house style) -----------------------
float ywHash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float ywNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = ywHash(i);
    float b = ywHash(i + vec2(1.0, 0.0));
    float c = ywHash(i + vec2(0.0, 1.0));
    float d = ywHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 5-octave fbm — the mist needs soft, layered structure so its "burning
// away" reads as wisps thinning rather than a flat fade.
float ywFbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * ywNoise(p);
        p = p * 2.02 + vec2(13.1, 7.3);
        a *= 0.5;
    }
    return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.y = 1.0 - uv.y;                       // host is top-origin

    vec4 term = texture(iChannel0, fragCoord / iResolution.xy);

    vec2 aspect = vec2(iResolution.x / iResolution.y, 1.0);

    // -- Breathing cycle (清輝發) ------------------------------------------
    // A slow ~24s loop. clarity ∈ [0,1]: 0 = fog gathered & moon dimmed,
    // 1 = fog burned away & radiance at peak. Eased so the clearing feels
    // like an inhale that releases light, then a slow re-gathering.
    float cyc = mod(iTime, 24.0) / 24.0;             // 0..1 seamless
    float breath = 0.5 - 0.5 * cos(cyc * 6.2831853); // smooth 0..1..0
    float clarity = smoothstep(0.0, 1.0, breath);    // ease the swell

    // -- Moon disc, top-center -------------------------------------------
    vec2 moonPos = vec2(0.5, 0.78);
    float R = 0.085;
    vec2 mp = (uv - moonPos) * aspect / R;           // local moon coords
    float r = length(mp);

    // Mirror-bright body: bright flat core with a soft limb so it reads as a
    // luminous "flying mirror" rather than a textured rock. Faint cool
    // banding gives the disc a touch of surface without dimming it.
    float disk = smoothstep(1.0, 0.86, r);
    float limb = sqrt(max(0.0, 1.0 - min(r * r, 1.0)));
    float band = 0.04 * ywFbm(mp * 2.1 + 5.0);
    vec3 moonColor = vec3(0.95, 0.965, 1.0);         // #f2f6ff cool-white
    // Disc brightness lifts with clarity (清輝發) but never fully dims.
    float moonBright = mix(0.62, 1.15, clarity);
    vec3 moonShaded = moonColor * (0.55 + 0.45 * limb + band) * moonBright;

    // -- Bloom halo -------------------------------------------------------
    // Two-scale exponential glow OUTSIDE the disc. Radius and intensity both
    // swell with clarity, so as the mist clears the radiance "pours forth".
    float outerR = max(r - 1.0, 0.0);
    // GW_GLOW widens the bloom RADII (softer/dreamier >1, crisper <1). The glow
    // is exp(-d * fall), so dividing the falloff by GW_GLOW stretches the soft
    // tail outward. Default 1.0 leaves the authored falloff untouched.
    float bloomFall = mix(5.5, 2.6, clarity) / GW_GLOW;  // wider glow when clear
    float bloomAmp  = mix(0.10, 0.42, clarity);
    float bloom = (exp(-outerR * bloomFall) * 0.85
                 + exp(-outerR * (1.1 / GW_GLOW)) * 0.18) * bloomAmp;
    bloom *= smoothstep(0.84, 1.02, r);              // only outside the disc

    // -- Volumetric ray-fan (清輝發) --------------------------------------
    // Soft angular spokes radiating from the moon. Only visible at peak
    // clarity, and only in the near field so it stays a halo, not a wash.
    float ang = atan((uv.y - moonPos.y), (uv.x - moonPos.x) * aspect.x);
    float spokes = 0.5 + 0.5 * sin(ang * 9.0 + 1.7);
    spokes = pow(max(spokes, 1e-4), 3.0);            // crisp the fan
    float rayReach = exp(-outerR * (2.3 / GW_GLOW)); // fade with distance (GW_GLOW widens the fan)
    float rays = spokes * rayReach * 0.22
               * smoothstep(0.95, 1.0, r)            // start at the limb
               * smoothstep(0.45, 1.0, clarity);     // only near peak

    // -- Jade-green drifting mist (綠煙) ----------------------------------
    // fBm fog that slowly drifts; its density is gated by (1 - clarity) so
    // it "burns away" as the cycle peaks then re-gathers. The envelope is
    // centred on the MOON's own latitude so the veil crosses the disc — the
    // drama of the poem is the moon being veiled then the mist滅盡, not a
    // low haze sitting beneath it. It still fades to nothing toward the
    // bottom so the lower screen (text) stays clear.
    vec2 fogUv = uv * aspect;
    float drift = mod(iTime, 90.0) * 0.012;          // slow continuous creep
    // GW_ENERGY scales the mist's AGITATION (its lateral wander amplitude),
    // NOT the drift RATE — so the dial reads as calm<->billowing wind instead
    // of teleporting the fog. A slow seamless sway gets amplified by eAmp, and
    // an extra gust grows ONLY above default. Default (1.0) leaves the authored
    // drift untouched (eAmp=1, gust=0), so the baseline is bit-identical.
    float eAmp = 0.45 + 0.55 * GW_ENERGY;            // 1.0 at default
    float sway = sin(mod(iTime, 37.0) * 0.21 + uv.x * 4.0) * 0.010 * (eAmp - 1.0);
    float gust = sin(mod(iTime, 29.0) * 0.33 + uv.y * 3.0) * 0.018 * max(GW_ENERGY - 1.0, 0.0);
    vec2 wander = vec2(sway + gust, gust * 0.5);
    float f1 = ywFbm(fogUv * 2.3 + vec2(drift, -drift * 0.6) + wander);
    float f2 = ywFbm(fogUv * 4.7 + vec2(-drift * 0.7, drift * 0.4) + 21.0 + wander * 1.3);
    float fog = f1 * 0.7 + f2 * 0.3;
    fog = smoothstep(0.42, 0.95, fog);               // wispy, not solid

    // Vertical envelope: a soft band hugging the moon's height (≈0.78),
    // tapering above the top edge and dying out by mid-screen so it never
    // crowds the text region below.
    float fogBand = smoothstep(0.46, 0.74, uv.y) * smoothstep(1.04, 0.82, uv.y);
    // GW_DENSITY scales how much the veil FILLS the disc's latitude (留白): >1
    // gathers a lusher, more occluding fog, <1 thins it toward clear sky. It
    // feeds both the mist glow and the disc occlusion below, so the whole veil
    // thickens/thins coherently. Default 1.0 = authored coverage.
    float fogDensity = fog * fogBand * (1.0 - clarity * 0.92) * GW_DENSITY;

    // Mist is luminous jade-grey, brightest where it catches the moonglow
    // (near the disc), so the veil itself reads as lit green smoke (綠煙).
    // Green channel kept clearly dominant so the hue reads as jade against
    // the blue-black ground rather than washing to neutral grey.
    float nearMoon = exp(-max(r - 1.0, 0.0) * 1.4);
    vec3 mistColor = vec3(0.24, 0.46, 0.34);         // jade #4a6b5a, greener
    vec3 mistGlow  = vec3(0.40, 0.64, 0.50);         // lit jade near the disc
    vec3 mist = mix(mistColor, mistGlow, nearMoon) * fogDensity * 0.6;

    // Where the mist is dense it also occludes the moon/bloom a little, so
    // the disc visibly dims behind the gathered fog.
    float veil = 1.0 - fogDensity * 0.55;

    // -- Composite (additive, luminous-on-dark) --------------------------
    vec3 effect = moonShaded * disk * veil
                + moonColor * bloom * veil
                + moonColor * rays
                + mist;

    effect = max(effect, 0.0);

    // GW_MOOD: a global warm/cool tone over the WHOLE scene (moon, bloom, rays,
    // and the jade mist alike) so the feeling reads at a glance — cool/silver
    // (-1) through the authored cool-white (0) to warm/lantern (+1). Default
    // 0 = identity (no shift).
    vec3 moodTint = GW_MOOD >= 0.0
        ? mix(vec3(1.0), vec3(1.18, 1.00, 0.80), GW_MOOD)   // warm: boost R, cut B
        : mix(vec3(1.0), vec3(0.82, 0.95, 1.20), -GW_MOOD); // cool: cut R, boost B
    effect *= moodTint;

    effect *= GW_POEM_INTENSITY;

    vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
    fragColor = vec4(outRgb, 1.0);
}
