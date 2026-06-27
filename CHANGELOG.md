# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Poem scene matcher.** The poller now selects a *poem* from live conditions
  instead of swapping literal weather scenes. Pluggable input providers
  (`libexec/ghostty-shaders/providers/`) emit JSON facts — weather, time-of-day,
  season, festival proximity; a declarative rule engine
  (`collections/poems.rules.json` + `scripts/match-rules.jq`) scores every poem
  against its affinity tags (`collections/poems.index.json`); and a
  temperature-controlled weighted-random pick (with a recency penalty) chooses
  one. `ghostty-shaders select [--print]` runs a match on demand; the
  LaunchAgent runs `select --cron`. Tunable via `collections/poems.conf` and
  `data/festivals.json` — and adding a new input is just a new provider file, no
  engine change.
- **WebGL2 web gallery** (`web/`), deployed to GitHub Pages: every scene
  running live in the browser from the exact `.glsl` sources, behind a
  simulated terminal screenful, with moon-phase / time-of-day / day-night
  controls that re-bake the swap `#define`s and recompile. Supports
  `#embed=1` (bare terminal window, for iframes) and `#t=<secs>`
  (deterministic fixed-time frame) URL modes, honors
  `prefers-reduced-motion`, and survives GPU context loss.
- **Dual-profile shader validation in CI**: every scene must compile under
  both the desktop GL wrapping (`bench/wrap-shader.sh`, default `gl410`)
  and the WebGL2 wrapping (`--profile es300`, shared byte-for-byte with
  the gallery via `web/glsl/`), pinning scenes to the portable GLSL
  subset.
- **README scene captures** (`assets/`), regenerated reproducibly by
  `scripts/capture-assets.sh` through the gallery's embed + fixed-time
  modes in headless Chrome.
- **Shader-portability ADR** (`docs/shader-portability.md`) recording the
  naga evaluation and the per-host-preamble decision.
- **Maintainer runbook** (`docs/publishing.md`), Dependabot coverage for
  GitHub Actions, and CI run deduplication (push trigger filtered to
  `main`).
- **Unit test suite** (`tests/run-tests.sh`) for the pure decision logic:
  the full WMO→scene mapping table, offline hour fallback, `.env` parsing,
  moon-phase math (synodic anchors, pre-epoch guard), day/night flag
  normalization, and the seconds-since-midnight octal trap. Dependency-free
  (bash + awk), runs on macOS and Linux, wired into CI. The scripts under
  test gained sourced-return guards so the harness can call their functions
  directly.

### Changed

- The `weather` subcommand is now poller + location management only
  (`on` / `off` / `set-city`); `weather on` installs the `select --cron`
  poller. Location resolution was extracted to a shared
  `scripts/location-lib.sh` used by the weather provider, `select`, and
  `weather`. `demo` now cycles the poem scenes.

### Removed

- **The six weather scenes** (`clear-day`, `clear-night`, `cloudy`, `rain`,
  `snow`, `thunderstorm`) and everything specific to them: the `pick_scene` /
  `scene_by_hour` WMO→scene mapping, the `moon-demo` command, the gallery's
  weather button group and moon / time-of-day / day-night controls, and their
  golden, baseline, and `assets/` capture files. Git history preserves them.

### Fixed

- **CI now validates the defines-injected shader variant** that both real
  hosts actually compile (`wrap-shader.sh --defines`, mirroring what
  `ghostty-shaders apply` and the gallery bake in). Previously only the
  `#ifndef`-fallback text was validated, so a scene defining a macro
  without a guard would pass CI and fail live with "macro redefined".
  Tag pushes and manual dispatch now also trigger CI, so release refs
  always have CI evidence.
- `scripts/capture-assets.sh` health-checks its local site server before
  shooting (a port collision previously produced error-page screenshots
  while reporting success), derives the default scene list from
  `shaders/scenes/` instead of a hand-copy, and picks the thunderstorm
  lightning frame by sweeping slots for the brightest render instead of
  trusting a baked-in timestamp.
- `moon_phase_at` prints fixed `%.6f` with a wrap guard — the awk default
  format could emit the literal `1` near a synodic wrap, violating the
  `[0,1)` contract of the baked `#define`.
- Gallery hardening: shader recompiles from slider drags are throttled
  (was: one compile per input event — main-thread stalls on slow GLSL
  compilers), URL-hash writes are debounced (Safari rate-limits
  `history.replaceState`), `devicePixelRatio` changes from monitor moves
  re-rasterize the canvas, the terminal-text canvas is reused instead of
  reallocated per rebuild, and the render loop parks entirely while
  paused with nothing pending instead of spinning at vsync.
- An unknown WMO weather code corrupted the scene name: `pick_scene()`'s
  diagnostic log went to stdout inside a command substitution, so the
  captured "scene" was the log line plus the scene. `log()` now writes to
  stderr (launchd merges both streams into the same log file, so the
  LaunchAgent's logging is unchanged).
- `moon_phase_at` now clamps pre-reference-epoch timestamps into `[0,1)`
  instead of returning a negative phase.

- Golden reference images were rendered vertically flipped: `glsl_image.c`
  applied the usual GL→PNG row reversal, but the scenes already interpret
  `fragCoord` as top-origin (Ghostty's Metal convention), so the reversal
  re-inverted them. Readback now emits scene-upright rows and all golden
  references are regenerated — they now match what Ghostty actually displays
  (moon and sun in the upper sky).

## [0.1.0] - 2026-06-08

### Added

- **Six weather-driven scenes** — `clear-day`, `clear-night`, `cloudy`,
  `rain`, `snow`, `thunderstorm` — mapping Open-Meteo WMO weather codes and
  the `is_day` flag to distinct GLSL background shaders.
- **Phase-accurate moon** in `clear-night`: terminator shape computed from
  the synodic cycle (29.53 days) and baked into the shader as
  `#define MOON_PHASE` at swap time, covering all eight lunar phases.
  Includes limb darkening, procedural maria and highland speckle, earthshine
  on the dark hemisphere, and a symmetric halo that dims toward new moon.
- **Pause/resume toggle** (`ghostty-shaders toggle`) for temporarily
  suspending weather-driven shader swaps without uninstalling the LaunchAgent.
  Manual `ghostty-shaders apply` calls override the paused state and re-enable
  polling.
- **Battery-aware automation** — optional `PAUSE_ON_BATTERY=true` in
  `config.env` pauses the shader on battery power and resumes on AC, checked
  at each poll via `pmset` (macOS only).
- **`.env`-based location config** (`~/.config/ghostty-shaders/config.env`):
  set `LAT`/`LON` directly (zero third-party calls) or `LOCATION` as a city
  name or US ZIP (geocoded once via Open-Meteo and cached in
  `location.json`). Interactive setup: `ghostty-shaders weather set-city`.
- **Self-installing 15-minute LaunchAgent** — `ghostty-shaders weather on`
  writes and loads a `launchd` plist under `~/Library/LaunchAgents/`;
  `ghostty-shaders weather off` removes it cleanly.
- **Compile-failure auto-revert** — `ghostty-shaders apply` reads Ghostty's
  unified log after signaling; if the new shader fails to compile it restores
  the previous shader file and re-signals, so a bad scene never leaves the
  terminal shaderless.
- **Headless GPU benchmark** (`bench/`) — `glsl_bench.c` creates an
  off-screen OpenGL 4.1 context via CGL (no window, no extra dependencies)
  and measures steady-state ms/frame for each scene. `bench/run-bench.sh`
  gates every scene at a configurable budget percentage (default **5%** of
  the 8.33 ms / 120 Hz frame budget). Scenes that exceed the threshold fail
  the build; the benchmark is the oracle for all future performance changes.
- `ghostty-shaders demo` command to cycle all six scenes for visual review.
- `ghostty-shaders moon-demo` command to cycle `clear-night` through all
  eight synthesized lunar phases.

### Changed

- Performance optimization — three scenes were originally over budget and
  were brought under 5% without visible quality loss:
  - `clear-night` (23% → 3.6%): moon-surface fbm now evaluated only for
    fragments inside the disk mask; the rest of the screen skips it entirely.
  - `cloudy` (18% → 4.6%): reduced from two 4-octave passes to one inlined
    2-octave pass; two-tone shading derived from the octaves already computed;
    fbm gated to the sky band where clouds are visible.
  - `snow` (6% → 3.2%): per-flake hash computed once per cell; sway
    computation moved behind a density early-out.

### Fixed

- New-moon halo no longer renders a one-sided glow — halo intensity now
  scales with the illuminated fraction (symmetric ring) rather than gating on
  the lit side direction, which previously flipped visibly through the synodic
  cycle.
- `ghostty-shaders apply` resolves its own real path via portable `readlink`
  before locating bundled scene files, so the command works correctly when
  invoked through the `~/.local/bin` symlink.

[Unreleased]: https://github.com/an0sunshy/ghostty-shaders/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/an0sunshy/ghostty-shaders/releases/tag/v0.1.0
