# Shader portability: one GLSL source, every host

**Status:** accepted · 2026-06-10

## Context

The six scenes must run on three hosts today, with a possible fourth later:

| Host | API | Who compiles the scene |
|---|---|---|
| Ghostty (the product) | Metal (macOS) / OpenGL (Linux) | Ghostty, internally (GLSL → SPIR-V → MSL via glslang/spirv-cross) |
| Bench harness (`bench/`) | OpenGL 4.1 core via CGL | `glsl_bench.c` / `glsl_image.c` |
| Web gallery (`web/`) | WebGL2 (GLSL ES 3.00) | the browser |
| *(future, maybe)* a wgpu renderer | WebGPU / native | would need WGSL or SPIR-V |

The question evaluated here: should a **translation layer** — specifically
[naga](https://github.com/gfx-rs/wgpu/tree/trunk/naga), the shader
translator behind wgpu — be the long-term shared layer that compiles one
source for all hosts? Or is plain GLSL, written carefully, already
portable enough?

## Decision

**The portability layer is the scene format itself, plus a per-host text
preamble.** Scenes are Shadertoy-subset GLSL bodies — `mainImage()` plus
helpers, no `#version`, no uniform declarations, no `main()` — and every
host wraps that body in a ~10-line preamble/epilogue and compiles it with
its own native compiler. No translation tooling is in the pipeline.

Concretely:

- Ghostty injects its own preamble at runtime (out of our hands, and the
  format we conform to).
- The bench harness wraps with `#version 410 core`
  (`bench/wrap-shader.sh`, default profile, mirrored from `glsl_bench.c`).
- The web gallery wraps with `#version 300 es`
  (`web/glsl/preamble.glsl` + `epilogue.glsl`, shared verbatim between the
  browser and `wrap-shader.sh --profile es300`).
- CI validates every scene under **both** profiles with glslangValidator,
  which is what pins scenes to the portable intersection going forward.

## Evidence

Empirical spike, June 2026. Tools: naga-cli **29.0.3**, glslang
**16.3.0** (Homebrew), all six scenes as input.

| Path tried | Result |
|---|---|
| Scene GLSL → naga GLSL frontend → WGSL | ❌ Frontend accepts only `#version 440/450/460 core` (no 410, no ES). After porting the wrapper to 460 + `layout(binding=…)`, it still fails on `uniform sampler2D iChannel0` with `Not implemented: variable qualifier`. |
| glslang `-V` (Vulkan) → SPIR-V → naga SPIR-V frontend | ❌ glslang compiles cleanly; naga rejects the module with `invalid id %42`, where `%42` is the `OpLoad` of the combined image-sampler. Persisted across `-g0`, `--target-env vulkan1.0`, and `spirv-opt --strip-debug`. |
| glslang `-G` (OpenGL) → SPIR-V → naga | ❌ `unsupported execution mode`. |
| Scene GLSL + `#version 300 es` preamble, validated as WebGL2 | ✅ **All six scenes valid GLSL ES 3.00 with zero translation tooling.** Shipped as the web gallery. |

The decisive observation: the only target that *seemed* to need
translation (the browser) accepts the scenes directly, because
Shadertoy-subset GLSL **is** GLSL ES modulo the preamble. A translation
layer would add a toolchain, a failure surface (see above — it fails
today), and a second dialect to debug, in exchange for nothing the text
preamble doesn't already deliver.

## What would change this

A **wgpu-based renderer** (e.g. a unified native+web bench harness, or a
WebGPU gallery) genuinely needs WGSL or SPIR-V. If that ever becomes a
goal, the viable entry point is glslang → SPIR-V → naga, contingent on
resolving the combined image-sampler `OpLoad` rejection (likely by
splitting `iChannel0` into separate texture/sampler objects in a
Vulkan-style wrapper, or by a naga fix upstream). That work is real and
should be justified by a real WebGPU requirement — not undertaken for
portability we already have.

## Consequences

- Scene authors write against the contract in
  [scene-authoring.md](scene-authoring.md); the dual-profile CI gate
  rejects anything outside the portable subset (e.g. GL-4-only builtins)
  at PR time.
- The web wrapping lives in `web/glsl/` and is consumed byte-for-byte by
  both the browser and CI — there is no second copy to drift.
- One asymmetry to know about: Ghostty hands scenes a **top-origin**
  `fragCoord` (Metal convention); GL/WebGL is bottom-origin. The web
  epilogue flips `gl_FragCoord.y` to present Ghostty's convention; the
  bench harness instead leaves the coordinate alone and reads back rows
  bottom-first (see `glsl_image.c`), which lands scene-upright in PNGs.
- Known debt: the gl410 wrapping still exists as three comment-synced
  copies (`glsl_bench.c`, `glsl_image.c`, and the `wrap-shader.sh`
  heredoc), unlike es300's shared files. Single-sourcing it the same way —
  the C harnesses reading a shared preamble file at runtime — is the
  obvious next refactor; until then, changing the bench wrapping means
  updating all three.
