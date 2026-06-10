# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

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
- **Pause/resume toggle** (`ghostty-weather-toggle`) for temporarily
  suspending weather-driven shader swaps without uninstalling the LaunchAgent.
  Manual `ghostty-weather-swap` calls override the paused state and re-enable
  polling.
- **Battery-aware automation** — optional `PAUSE_ON_BATTERY=true` in
  `config.env` pauses the shader on battery power and resumes on AC, checked
  at each poll via `pmset` (macOS only).
- **`.env`-based location config** (`~/.config/ghostty-weather/config.env`):
  set `LAT`/`LON` directly (zero third-party calls) or `LOCATION` as a city
  name or US ZIP (geocoded once via Open-Meteo and cached in
  `location.json`). Interactive setup: `ghostty-weather-poll --set-city`.
- **Self-installing 15-minute LaunchAgent** — `ghostty-weather-poll --install`
  writes and loads a `launchd` plist under `~/Library/LaunchAgents/`;
  `--uninstall` removes it cleanly.
- **Compile-failure auto-revert** — `ghostty-weather-swap` reads Ghostty's
  unified log after signaling; if the new shader fails to compile it restores
  the previous shader file and re-signals, so a bad scene never leaves the
  terminal shaderless.
- **Headless GPU benchmark** (`bench/`) — `glsl_bench.c` creates an
  off-screen OpenGL 4.1 context via CGL (no window, no extra dependencies)
  and measures steady-state ms/frame for each scene. `bench/run-bench.sh`
  gates every scene at a configurable budget percentage (default **5%** of
  the 8.33 ms / 120 Hz frame budget). Scenes that exceed the threshold fail
  the build; the benchmark is the oracle for all future performance changes.
- `ghostty-weather-demo` command to cycle all six scenes for visual review.
- `ghostty-weather-moon-demo` command to cycle `clear-night` through all
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
- `ghostty-weather-swap` resolves its own real path via portable `readlink`
  before locating bundled scene files, so the command works correctly when
  invoked through the `~/.local/bin` symlink.

[Unreleased]: https://github.com/an0sunshy/ghostty-weather/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/an0sunshy/ghostty-weather/releases/tag/v0.1.0
