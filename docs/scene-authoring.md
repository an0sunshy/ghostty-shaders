# Scene authoring guide

This document covers everything you need to write a new weather scene for
ghostty-shaders: the shader contract Ghostty expects, the baked defines the
swap pipeline injects, performance discipline, and the steps to finish a scene
and get it merged.

For the mechanical steps — where to put the file, how to wire it into the
weather→scene mapping, what checks to run before opening a PR — see
[CONTRIBUTING.md](../CONTRIBUTING.md).

---

## Entry point

Every scene is a GLSL fragment shader with a single entry point:

```glsl
void mainImage(out vec4 fragColor, in vec2 fragCoord)
```

`fragCoord` is the fragment's position in pixels, with the origin at the
**top-left** of the window — Ghostty renders through Metal on macOS and
hands shaders Metal's top-origin convention, not OpenGL's bottom-origin one.
Every scene flips once (`uv.y = 1.0 - uv.y`) so "high `uv.y`" reads as "top
of sky"; follow the same pattern. (Hosts with a bottom-origin
`gl_FragCoord` compensate in their wrappers — see
[shader-portability.md](shader-portability.md).) The shader is invoked once
per visible pixel per frame.

---

## Uniforms

Ghostty supplies four uniforms to every custom shader:

| Uniform | Type | Description |
|---|---|---|
| `iResolution` | `vec3` | Window size in pixels. `.x` = width, `.y` = height. `.z` is unused; treat it as 1.0. |
| `iTime` | `float` | Elapsed time in seconds since the shader was loaded. Monotonically increasing. |
| `iChannel0` | `sampler2D` | The terminal's glyph/text layer, composited at full opacity. Alpha encodes glyph coverage. |
| `iBackgroundColor` | `vec3` | The user's configured Ghostty background color, linear RGB. This is a Ghostty extension — it is not part of the Shadertoy uniform spec. |

`iChannel0` and `iBackgroundColor` together are what let your scene sit behind
the terminal contents while respecting the user's color scheme. Use them in the
composite at the end of every shader (see the next section).

---

## Mandatory text-passthrough composite

Every scene must end with this exact pattern so glyphs remain fully legible:

```glsl
vec4 term = texture(iChannel0, fragCoord / iResolution.xy);
vec3 outRgb = (iBackgroundColor + effect) * (1.0 - term.a) + term.rgb;
fragColor = vec4(outRgb, 1.0);
```

`effect` is the additive weather contribution your shader computes — color
deltas on top of the background, not a replacement for it. Where `term.a` is
1.0 (opaque glyph), the background is completely suppressed; where it is 0.0
(empty cell), your effect shows through at full strength.

Do not premultiply `iBackgroundColor` into your effect before this step — the
composite handles it.

---

## Composition & motion craft

The contract above gets a scene to compile and keep text legible. These three
rules are what separate a scene that reads as intended from one that looks
broken or muddy. They apply to every collection.

### Render luminous fields, not figures

The additive-on-dark style renders **fields and phenomena** — snow, fog,
moonlight, rain, water, fire, smoke, cloud — beautifully, because each is just
light scattered across many particles or a soft gradient. It renders
**recognizable figure-objects** — a bird, a boat, a horse, a person, a lone
sail — badly: a small hard silhouette over a luminous field reads as a sprite,
not poetry, and no amount of detail fixes it.

Before committing to an image, apply the test: **does the key image reduce to
light / particle / field with no loss?** A firefly passes — it *is* a moving
point of light. An egret or a wild-duck glyph fails — its meaning is its shape.
If the poem's central image is a figure, do one of:

- **寫意 (xiěyì) — render the trace, not the silhouette.** Show the figure's
  effect on the field: the wake, not the boat; the disturbed water, not the
  fish; the gust, not the bird.
- **Pick a different line.** Most poems carry several images; choose the one
  that is already a field — the sunset, the river, the snow — and let the
  figure go.
- Failing both, the scene doesn't belong in this style. Curate it out rather
  than ship a sprite.

This is a curation criterion, not a code check — there is no blocklist.
Examples handled on these grounds: the boat in `zao-fa-baidi` and the egret in
`yu-ge-zi` were curated out; the lone sail was stripped from `wang-tianmen-shan`,
keeping the cliffs-and-sun field-scene that stood on its own.

### Move natural effects in the physically correct direction

A field only reads as itself if it moves the way the real phenomenon moves.
Snow and rain **fall** — downward, with wind adding a diagonal, never upward;
smoke and mist **rise**; water and current **flow downhill / downstream**; a
setting sun **sinks**. A reversed or purely-sideways motion vector is the most
common way these scenes look broken: the eye reads "snow", sees it drift up,
and rejects the whole frame.

Two checks when you write an advection term:

1. **State the motion vector in a comment** (`// snow: down-and-left, ~27° off
   vertical`) and confirm its sign against the top-left origin. High `uv.y` is
   the top of the sky, so "falling" means the sampled field scrolls so that
   features move toward *lower* `uv.y` over time — get the sign right.
2. **Orient streaks along the travel axis.** Elongated snow/rain streaks must
   lie *along* the direction of motion, not across it. A streak raked one way
   while the field moves another reads as a glitch.

`feng-xue-su` shipped with its snow rising up-and-left — the streaks were
oriented correctly but advected against gravity, so the gale looked wrong. The
fix was a single sign flip on the downwind axis plus matching the veil scroll.

### Bias the focal element to the right

This is a terminal background: the user's prompt, commands, and output are
densest on the **left** and top-left and thin out toward the right, so the
right side is the most "vacant" canvas. When a scene has a single focal
element — a waterfall, the sun or moon, a lantern, a beacon — place it **right
of center** (roughly the right third) so it sits where the text isn't, and keep
the left two-thirds open. This composes with 留白: 留白 keeps the center
vertically clear for legibility; the right-bias chooses *which* side the bright
mass lives on.

Broad, frameless fields — an even snowfall, a full-width sea swell, drifting
fog — have no single focus and need no bias; spread them across the frame as
the phenomenon would naturally fall. `wang-lushan-pubu` moves its whole
cataract — column, spray, basin, haze — into the right third for exactly this
reason.

---

## Baked defines

The swap pipeline prepends several `#define` lines to the scene before writing
it to the cache. These let the shader respond to real-world conditions (time
of day, lunar phase) without requiring Ghostty to expose date/clock uniforms.

| Define | Type | Range / values | Notes |
|---|---|---|---|
| `MOON_PHASE` | `float` | [0, 1) | 0 = new, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter. Computed from the synodic cycle (29.53 days) at swap time. Used by `clear-night`. |
| `IS_DAY` | `float` | 0.0 or 1.0 | Open-Meteo's `is_day` flag. 1.0 = daytime, 0.0 = night. Used for lighting decisions in `cloudy` and others. |
| `TIME_OF_DAY_BASE` | `float` | seconds since midnight | Local solar time at swap time, as a float. Can drive color temperature shifts or gradual sky transitions. |

Guard every define you consume with `#ifndef` so the scene compiles
stand-alone in the bench harness and in Shadertoy-style GLSL validators:

```glsl
#ifndef MOON_PHASE
#define MOON_PHASE 0.5
#endif

#ifndef IS_DAY
#define IS_DAY 1.0
#endif

#ifndef TIME_OF_DAY_BASE
#define TIME_OF_DAY_BASE 43200.0   // noon as a sensible default
#endif
```

Only include guards for the defines your scene actually reads. Unused guards
are harmless noise.

---

## Performance discipline

These shaders run as a full-screen fragment pass every frame the terminal is
visible. Cost scales with `pixels × refresh × per-pixel work`. At 3456×2234
and 120 Hz, the per-frame budget is 8.33 ms; every scene must stay under 5%
of that (≈ 0.42 ms) on an M1 Max. The benchmark is the oracle — a scene that
fails the gate needs optimization, not a raised threshold.

### The dominant cost driver: procedural noise

Fractional Brownian motion (`fbm`) — layered octaves of value or gradient
noise — is the main cost in every scene that uses it. One pass across the full
screen at four octaves can consume the entire budget on its own. The two levers
that matter on Apple Silicon:

**1. Gate expensive noise to where it is actually visible.**

Do not compute fbm for every fragment and then multiply by zero outside the
region of interest. Branch early and skip the work entirely.

`clear-night` gates its 3-octave moon-surface fbm to inside the moon disk:

```glsl
if (r < 1.05) {
    moonShaded = moonSurface(lp);
    // earthshine also inside this block
}
```

The moon disk covers less than 1% of the screen, so entire GPU warps outside
the disk skip the fbm uniformly. This cut the scene's cost from 23% to 3.6% —
a 6× reduction with zero visual change.

`cloudy` gates its 2-octave fbm to the sky band where clouds appear:

```glsl
float vbias = smoothstep(0.95, 0.55, uv.y) * smoothstep(0.30, 0.55, uv.y);

if (vbias > 0.0) {
    // all cloud fbm inside this block
}
```

The bottom ~30% and top ~5% of the screen are unconditionally zero and skip
all cloud work. This cut the scene from 18% to 4.6%.

**2. Reduce octave count.**

Each additional fbm octave doubles the noise sample count. Go from four octaves
to two; verify visually that the scene still reads correctly. In most cases
the coarser result is indistinguishable at terminal viewing distances.

**3. A cheaper hash does NOT help on Apple Silicon.**

The standard hash used across all scenes —
`fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453)` — uses the GPU's
built-in `sin()`. On Apple Silicon the GPU's `sin()` is fast, and replacing
it with a polynomial hash was measured to be slower in practice, not faster.
Do not attempt this optimization.

### Benchmark command

```sh
bench/run-bench.sh
```

This builds `bench/glsl_bench.c` (requires Xcode command-line tools; macOS
only) and runs each scene at 3456×2234 / 120 Hz, printing each scene's
ms/frame and percentage of the frame budget. The script exits non-zero and
prints `OVER` for any scene above the threshold. Run it before every commit
that touches a shader.

---

## Previewing your scene

Apply the scene to a running Ghostty instance immediately:

```sh
ghostty-shaders apply <name>
```

Cycle all scenes in sequence (10 seconds each by default):

```sh
ghostty-shaders demo [seconds]
```

If your scene is `clear-night` or uses `MOON_PHASE`, preview all eight
synthesized lunar phases:

```sh
ghostty-shaders moon-demo [seconds]
```

---

## Both host profiles must compile

Scenes are written in the portable GLSL subset that compiles everywhere the
project runs them: Ghostty itself, the desktop-GL bench harness, and the
WebGL2 gallery. CI rejects a scene that breaks either wrapper; check
locally with:

```sh
bench/wrap-shader.sh                 shaders/<category>/<name>.glsl > /tmp/s.frag
bench/wrap-shader.sh --profile es300 shaders/<category>/<name>.glsl > /tmp/s-es.frag
glslangValidator /tmp/s.frag /tmp/s-es.frag
```

Practically this means: no GL-4-only built-ins, `texture()` not
`texture2D()`, and float literals where GLSL ES requires them. The
rationale and the evaluated alternatives live in
[shader-portability.md](shader-portability.md).

---

## The golden-image step

Every scene has a committed reference render under `bench/golden/`; CI
re-renders each scene deterministically and fails on drift beyond a
tolerance. A brand-new scene fails with `MISSING reference` until you
record one:

```sh
bench/golden.sh update    # renders + records bench/golden/<name>.png
bench/golden.sh check     # verify: all scenes within tolerance
```

Commit the new PNG with your scene. Separately, run `bench/run-bench.sh`
and include its table in your PR description as described in
[CONTRIBUTING.md](../CONTRIBUTING.md).
