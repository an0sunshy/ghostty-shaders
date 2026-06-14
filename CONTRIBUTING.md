# Contributing to ghostty-shaders

## Dev setup

```sh
git clone https://github.com/an0sunshy/ghostty-shaders.git ~/dev/ghostty-shaders
cd ~/dev/ghostty-shaders
./install.sh          # symlinks commands + wires the Ghostty include
```

You need Ghostty installed and running. The bench harness additionally
requires a macOS host with Xcode command-line tools (for `clang` and the
OpenGL/CGL frameworks). The poller, LaunchAgent, and battery-awareness code
are macOS-specific; the shaders and manual swap/demo commands work on Linux
Ghostty too.

## Repo layout

The README carries a [condensed top-level view](README.md#layout); the full
file-by-file tree lives here.

```text
bin/
  ghostty-shaders             the single dispatcher (the only command on PATH)
libexec/ghostty-shaders/      subcommand implementations (not on PATH):
  apply                       apply a scene + reload Ghostty
  weather                     fetch weather, pick scene, apply; LaunchAgent installer
  toggle                      pause / resume
  demo                        cycle the weather scenes
  moon-demo                   cycle lunar phases
shaders/
  weather/                    the six weather scene shaders (.glsl)
  poems/                      animated classical-poem scenes (.glsl)
collections/
  weather.conf, poems.conf    per-collection manifest (description, strategy)
web/
  index.html, gallery.js,     WebGL2 scene gallery (the GitHub Pages demo)
  style.css
  glsl/preamble.glsl,         ES wrapping — single source for the browser
  glsl/epilogue.glsl          AND CI validation (wrap-shader.sh es300)
scripts/
  scene-discovery.sh          shared scene lookup (one source of truth)
  ghostty-process.sh          shared Ghostty pid matcher + reload signal
  build-site.sh               assemble the gallery site (Pages + local preview)
  serve-site.sh               serve the exact Pages layout locally
  capture-assets.sh           regenerate assets/ via headless Chrome
tests/
  run-tests.sh                unit tests for the decision logic (CI: ubuntu)
bench/
  glsl_bench.c                headless GPU timing harness (CGL/OpenGL)
  glsl_image.c                deterministic per-scene PNG renderer (golden)
  run-bench.sh                build + benchmark all scenes, gate on % budget
  wrap-shader.sh              wrap a scene into a stand-alone frag for validation
  golden.sh                   render + diff scenes against committed references
  golden/                     committed golden reference images (one per scene)
  baseline.json               recorded per-scene benchmark numbers
docs/
  scene-authoring.md          shader conventions, uniforms, baked defines
  shader-portability.md       ADR: why per-host preambles, not a translator
  performance.md              the compute gate, harness, and tuning
  review-personas.md          the review panel (Claude Code subagents)
  publishing.md               maintainer runbook: first publish + releases
  random-per-window.md        the deferred per-new-window random rotation
  poem-titles.md              English-title choices + sources for the poems
.claude/agents/               the 6 review personas (oss-maintainer, end-user-
                              advocate, security-reviewer, perf-gpu-engineer,
                              accessibility-legibility, visual-regression-qa)
.github/                      CI + Pages workflows, dependabot, issue/PR templates
assets/                       gallery scene captures (scripts/capture-assets.sh)
install.sh                    installer / uninstaller
LICENSE                       MIT
CONTRIBUTING.md               dev setup + how to add a scene
CODE_OF_CONDUCT.md            contributor conduct
SECURITY.md                   threat model + how to report a vulnerability
CHANGELOG.md                  Keep a Changelog / semver history
.editorconfig                 shared editor settings
.markdownlint-cli2.jsonc      markdown lint config (CI-enforced)
```

## Adding a new scene

1. **Write the shader.** Drop `shaders/<category>/<name>.glsl` (e.g.
   `shaders/weather/` or `shaders/poems/`) following the conventions in the
   existing scenes. Scene names are globally unique across categories:

   - Entry point: `void mainImage(out vec4 fragColor, in vec2 fragCoord)`.
   - Background-only. Sample `iChannel0` (the glyph layer) and composite at the
     end so text stays legible:

     ```glsl
     vec4 term = texture(iChannel0, fragCoord / iResolution.xy);
     // ... compute effect ...
     vec3 bgFinal = iBackgroundColor + effect;
     vec3 outRgb = bgFinal * (1.0 - term.a) + term.rgb;
     fragColor = vec4(outRgb, 1.0);
     ```

   - Guard every baked `#define` with `#ifndef` so the scene compiles
     stand-alone in the bench harness and in Shadertoy-style validators:

     ```glsl
     #ifndef IS_DAY
     #define IS_DAY 1.0
     #endif
     ```

   - See `docs/scene-authoring.md` for the full uniform list, all baked
     defines, and performance guidance.

2. **Pass the performance gate.** Every scene must stay under 5% of the
   8.33 ms/frame budget at 3456×2234 / 120 Hz on an M1 Max:

   ```sh
   bench/run-bench.sh
   ```

   The script exits non-zero and prints `OVER` for any scene above the
   threshold. The benchmark is the oracle — if a scene fails, it needs
   optimization before it can merge, not a raised threshold. The dominant cost
   driver is procedural noise (fbm) evaluated per pixel. The two levers that
   matter on Apple Silicon are: **gate** expensive noise to where it is
   actually visible (see how `clear-night` evaluates its moon-surface fbm only
   inside the disk, and how `cloudy` gates its fbm to the sky band), and
   **reduce octave count / sample count**. A cheaper hash function does NOT
   help on Apple Silicon — the GPU's `sin()` is fast and a polynomial hash
   replacement measured slower in practice.

3. **Wire it into the weather→scene mapping.** (Weather scenes only.) Add the
   new scene name to the `pick_scene()` function in
   `libexec/ghostty-shaders/weather`, mapping the appropriate WMO weather codes
   to it. Keep the existing codes that already
   point to the scene you're replacing (e.g., `fog.glsl` would claim codes
   45 and 48 currently mapped to `cloudy`). Extend the mapping table in
   `tests/run-tests.sh` to pin the new codes.

4. **Test manually.**

   ```sh
   ghostty-shaders apply <name>          # apply it immediately
   ghostty-shaders demo                 # cycle all scenes including the new one
   ```

5. **Record the golden reference.** CI fails any scene without a committed
   reference render (`MISSING reference`):

   ```sh
   bench/golden.sh update               # writes bench/golden/<name>.png
   git add bench/golden/<name>.png
   ```

6. **Register it in the web gallery.** Add a picker button in
   `web/index.html` (`data-scene="<name>"` — the gallery derives its scene
   list from those buttons), a `SCENE_WMO` entry in `web/gallery.js` for
   the simulated terminal text, and a `params_for` entry in
   `scripts/capture-assets.sh`. A unit test fails if the scenes under
   `shaders/` and the picker buttons drift apart, and the capture script errors on a
   scene without params — neither can be skipped silently.

## Adding a new collection

A collection is just a `shaders/<collection>/` folder of scenes (names stay
globally unique across all collections). To add one:

1. Create `shaders/<collection>/` and drop scenes in it as above.
2. Add `collections/<collection>.conf` with a one-line `description` (shown by
   `ghostty-shaders list`) and a `strategy` (`static` for pick-and-keep, or
   `poller` if it drives itself like `weather`).
3. Register each scene's gallery button (step 6 above).

`use`, `random`, `list`, the build, the benchmarks, and the gallery==scenes test
all discover scenes recursively, so no other wiring is needed. Only `weather` has
a bespoke poller; a `static` collection needs no code.

## Running the checks

All shell scripts must pass shellcheck with no errors:

```sh
shellcheck bin/ghostty-shaders libexec/ghostty-shaders/* \
  bench/*.sh scripts/*.sh tests/*.sh install.sh
```

The decision logic (WMO→scene mapping, moon phase, `.env` parsing,
day/night normalization) is unit-tested. The suite is dependency-free
(plain bash + awk), runs on macOS and Linux, and must pass:

```sh
tests/run-tests.sh
```

Scenes must validate under **both** host profiles — desktop GL (the bench
harness / Ghostty stand-in) and WebGL2 (the web gallery):

```sh
bench/wrap-shader.sh                 shaders/<category>/<name>.glsl > /tmp/s.frag
bench/wrap-shader.sh --profile es300 shaders/<category>/<name>.glsl > /tmp/s-es.frag
glslangValidator /tmp/s.frag /tmp/s-es.frag
```

macOS ships `bash 3.2`. Scripts must be compatible — no `${var,,}` or
`${var^^}` (use `tr` instead), no `declare -A`, no `local -n`.

## Cross-platform expectations

Changes must work on **macOS and Linux Ghostty**. The poller
(`ghostty-shaders weather`), LaunchAgent install/uninstall, battery awareness
(`pmset`), and compile-validation (`/usr/bin/log`) are macOS-only and must
degrade gracefully on Linux (skip, not crash). The shaders, `swap`, `toggle`,
and `demo` commands must work on both platforms.

Portability rules for shell scripts:

- Shebang: `#!/usr/bin/env bash`
- Avoid GNU-only flags: use `tail -c` not `truncate(1)`, bare `readlink` not
  `readlink -f`, `wc -c` not `stat --printf`, POSIX `sed -i ''` / `sed -i`
  split by platform if in-place editing is needed.

## Commit style

The repo uses a `ghostty-shaders: <summary>` prefix for every commit message.
Match it:

```text
ghostty-shaders: add fog scene with depth-layered fbm
```

One feature or fix per commit. Squash fixups before requesting review.
Keep PRs in draft until you're ready for a full review pass.

## Pull requests

- Run `bench/run-bench.sh` and paste the output table in the PR description.
- Run `tests/run-tests.sh`; all assertions must pass.
- Run `shellcheck` on any modified scripts; fix all findings.
- PR descriptions must describe the current state of the change, not a diff
  narrative. A reader unfamiliar with the previous version should understand
  what the PR does and why.
- Update `CHANGELOG.md` under `## [Unreleased]`.
