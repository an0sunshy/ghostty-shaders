# Scene authoring guide

This document covers everything you need to write a new weather scene for
ghostty-weather: the shader contract Ghostty expects, the baked defines the
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
bottom-left of the window (standard OpenGL convention). The shader is invoked
once per visible pixel per frame.

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
ghostty-weather-swap <name>
```

Cycle all scenes in sequence (3 seconds each by default):

```sh
ghostty-weather-demo [seconds]
```

If your scene is `clear-night` or uses `MOON_PHASE`, preview all eight
synthesized lunar phases:

```sh
ghostty-weather-moon-demo [seconds]
```

---

## The golden-image step

Before opening a PR, run the golden-image script to record your scene's
benchmark baseline:

```sh
bench/golden.sh
```

This captures the current `bench/run-bench.sh` output and saves it as the
reference for future comparisons. Include the benchmark table in your PR
description as described in [CONTRIBUTING.md](../CONTRIBUTING.md).
