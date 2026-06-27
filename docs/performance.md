# Performance: the compute gate

These shaders run as a full-screen fragment pass every frame the terminal is
visible, so their cost is `pixels × refresh × per-pixel work`. The benchmark in
`bench/` measures each scene's steady-state GPU time and reports it as a
percentage of the display's per-frame budget (8.33 ms at 120 Hz). CI and the
maintainer gate every scene under its **collection's** budget — `budget_pct` in
`collections/<collection>.conf`. The budget is per-collection because cost
tolerance is a property of how a collection is used: the opt-in poem art a user
selects by hand carries a high ceiling (`poems` = **75%**), where an always-on
poller-driven collection would carry a low one. The current per-scene numbers
live in the [Performance snapshot](../README.md#performance) in the README.

```sh
bench/run-bench.sh            # build + benchmark all scenes at 3456×2234
```

## The harness

`bench/glsl_bench.c` is a self-contained headless harness: it creates an
off-screen OpenGL 4.1 context via CGL (no window, no dependencies beyond macOS
system frameworks), wraps each scene in the same four uniforms Ghostty supplies
(`iResolution`, `iTime`, `iChannel0`, `iBackgroundColor`), and times
steady-state ms/frame over many trials. Additive blending across frames defeats
the tile-GPU dead-frame elimination that would otherwise collapse the timing to
zero.

**Caveat:** macOS OpenGL is itself layered over Metal, so the absolute ms is a
proxy for Ghostty's native-Metal pipeline. The relative ranking between scenes
and the order-of-magnitude budget % are sound — which is what the gate needs.

## Tuning a scene

Tunables are environment variables (`GHOSTTY_SHADERS_BENCH_W`/`_H`,
`GHOSTTY_SHADERS_REFRESH_HZ`, `GHOSTTY_SHADERS_BUDGET_PCT`); see the script
header. The dominant cost driver is procedural noise (fbm) evaluated per pixel,
so the levers that matter are **gating** it to where it is actually visible and
**reducing octaves / samples** — on Apple Silicon a cheaper *hash* does not
help, since the GPU's `sin()` is fast and a polynomial replacement measured
slower.

The clearest worked examples of these levers come from the original weather
collection (since removed). Each scene started over budget and was optimized
down without changing its character — the techniques transfer unchanged to any
scene:

- **Gate noise to its region (lossless).** A clear-night scene's 3-octave
  moon-surface noise, evaluated only inside the moon disk instead of across the
  whole screen, fell from 23% to 3.6% — the disk is under 1% of the frame, so
  the warps outside it skip the fbm entirely.
- **Collapse and reuse octaves.** A cloudy scene dropped from two 4-octave fbm
  passes to one inlined 2-octave pass — with the shading cue derived from the
  octaves it already had, gated to the sky band — taking it from 18% to 4.6%.
- **Early-out before the cheap-but-frequent work.** A snowfall scene that
  hashes each cell once and moves the per-flake sway *behind* the density
  early-out went from 6% to 3.2%.

The benchmark is the oracle for any future scene change.
