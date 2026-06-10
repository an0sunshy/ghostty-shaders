# Contributing to ghostty-weather

## Dev setup

```sh
git clone <this-repo> ~/dev/ghostty-weather
cd ~/dev/ghostty-weather
./install.sh          # symlinks commands + wires the Ghostty include
```

You need Ghostty installed and running. The bench harness additionally
requires a macOS host with Xcode command-line tools (for `clang` and the
OpenGL/CGL frameworks). The poller, LaunchAgent, and battery-awareness code
are macOS-specific; the shaders and manual swap/demo commands work on Linux
Ghostty too.

## Repo layout

See the [Layout section of the README](README.md#layout) — the tree is
maintained in one place so it can't drift.

## Adding a new scene

1. **Write the shader.** Drop `shaders/scenes/<name>.glsl` following the
   conventions in the existing scenes:

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

3. **Wire it into the weather→scene mapping.** Add the new scene name to the
   `pick_scene()` function in `bin/ghostty-weather-poll`, mapping the
   appropriate WMO weather codes to it. Keep the existing codes that already
   point to the scene you're replacing (e.g., `fog.glsl` would claim codes
   45 and 48 currently mapped to `cloudy`). Extend the mapping table in
   `tests/run-tests.sh` to pin the new codes.

4. **Test manually.**

   ```sh
   ghostty-weather-swap <name>          # apply it immediately
   ghostty-weather-demo                 # cycle all scenes including the new one
   ```

5. **Record the golden reference.** CI fails any scene without a committed
   reference render (`MISSING reference`):

   ```sh
   bench/golden.sh update               # writes bench/golden/<name>.png
   git add bench/golden/<name>.png
   ```

## Running the checks

All `bin/` scripts and `*.sh` files must pass shellcheck with no errors:

```sh
shellcheck bin/ghostty-weather-* bench/*.sh scripts/*.sh tests/*.sh install.sh
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
bench/wrap-shader.sh                 shaders/scenes/<name>.glsl > /tmp/s.frag
bench/wrap-shader.sh --profile es300 shaders/scenes/<name>.glsl > /tmp/s-es.frag
glslangValidator /tmp/s.frag /tmp/s-es.frag
```

macOS ships `bash 3.2`. Scripts must be compatible — no `${var,,}` or
`${var^^}` (use `tr` instead), no `declare -A`, no `local -n`.

## Cross-platform expectations

Changes must work on **macOS and Linux Ghostty**. The poller
(`ghostty-weather-poll`), LaunchAgent install/uninstall, battery awareness
(`pmset`), and compile-validation (`/usr/bin/log`) are macOS-only and must
degrade gracefully on Linux (skip, not crash). The shaders, `swap`, `toggle`,
and `demo` commands must work on both platforms.

Portability rules for shell scripts:

- Shebang: `#!/usr/bin/env bash`
- Avoid GNU-only flags: use `tail -c` not `truncate(1)`, bare `readlink` not
  `readlink -f`, `wc -c` not `stat --printf`, POSIX `sed -i ''` / `sed -i`
  split by platform if in-place editing is needed.

## Commit style

The repo uses a `ghostty-weather: <summary>` prefix for every commit message.
Match it:

```text
ghostty-weather: add fog scene with depth-layered fbm
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
