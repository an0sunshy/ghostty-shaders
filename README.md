# ghostty-weather

Live, weather-driven background shaders for the [Ghostty](https://ghostty.org)
terminal. A small daemon polls your local weather every 15 minutes and swaps
Ghostty's `custom-shader` to match — clear day, clear night (with a
phase-accurate moon), clouds, rain, snow, or thunderstorm — reloading every
open window in place, no restart.

Text stays fully legible: every scene renders **behind** the terminal contents
and lets the glyph layer pass through untouched.

---

## How it works

```
 ┌─ ghostty-weather-poll ─┐      ┌─ ghostty-weather-swap ─┐      ┌─ Ghostty ─┐
 │ Open-Meteo current     │      │ pick scene .glsl       │      │ reload    │
 │ weather + is_day  ─────┼─────▶│ bake moon-phase/time   │─────▶│ config    │
 │ (LaunchAgent, 15 min)  │      │ write active.conf      │      │ recompile │
 └────────────────────────┘      │ kill -USR2 ghostty ────┼─────▶│ shader    │
                                  └────────────────────────┘      └───────────┘
```

1. **`ghostty-weather-poll`** fetches the current condition from Open-Meteo
   (free, no API key) for your configured location and maps the
   [WMO weather code](https://open-meteo.com/en/docs) + day/night flag to one
   of six scenes.
2. **`ghostty-weather-swap`** copies that scene to a fresh file in
   `~/Library/Caches/ghostty-weather/`, prepends the current
   time-of-day and moon-phase as `#define`s, points `active.conf` at it, and
   signals Ghostty to reload.
3. **Ghostty** reloads its config on `SIGUSR2` and recompiles the shader for
   every open surface — the new sky appears within a frame.

If the new scene fails to compile, the swap detects it in Ghostty's log and
reverts to the previous one, so a bad edit never leaves you shaderless.

## Requirements

- **Ghostty** with `SIGUSR2` config-reload support (tested on 1.3.1).
- **macOS** for the automatic poller (`launchd`) and the compile-validation
  step (`/usr/bin/log`). The shaders and the manual `swap`/`toggle`/`demo`
  commands work on Linux Ghostty too — see [Cross-platform](#cross-platform).
- `curl`. `jq` is optional (used if present; there's a grep fallback).

## Install

```sh
git clone <this-repo> ~/dev/ghostty-weather
cd ~/dev/ghostty-weather
./install.sh                 # links commands + wires the Ghostty include
# or, in one shot, also start the auto-poller:
./install.sh --with-poller
```

`install.sh` symlinks the commands into `~/.local/bin` and adds an absolute
`config-file = ?…/active.conf` line to Ghostty's always-loaded secondary
config (`~/Library/Application Support/com.mitchellh.ghostty/config` on macOS),
so it works regardless of how your main config is managed.

## Usage

```sh
ghostty-weather-swap clear-night     # apply a scene now (manual)
ghostty-weather-toggle               # pause / resume the shader
ghostty-weather-toggle --status      # show current scene / paused state
ghostty-weather-poll                 # poll once and swap to match weather
ghostty-weather-poll --install       # install the 15-min LaunchAgent
ghostty-weather-poll --uninstall     # remove it
ghostty-weather-demo [seconds]       # cycle every scene for a visual review
ghostty-weather-moon-demo [seconds]  # cycle clear-night through all 8 lunar phases
```

Scenes: `clear-day` · `clear-night` · `cloudy` · `rain` · `snow` ·
`thunderstorm` (fog maps to `cloudy` for now).

## Configuration

Location and behavior live in `~/.config/ghostty-weather/config.env`:

```sh
# Pick ONE location source.
# Direct coordinates — never calls any third party for location:
LAT=47.6062
LON=-122.3321
# ...or a city / US ZIP, geocoded ONCE via Open-Meteo and cached forever:
LOCATION="Seattle, WA"     # or: LOCATION=98101

# Pause the shader on battery, resume on AC (opt-in):
PAUSE_ON_BATTERY=true
```

Or set the location interactively:

```sh
ghostty-weather-poll --set-city "Seattle, WA"
```

Direct `LAT`/`LON` make **zero** third-party calls. A city/ZIP is geocoded a
single time and cached in `location.json`; subsequent polls reuse it.

### Weather → scene mapping

| WMO codes | Scene |
|---|---|
| 0, 1 | `clear-day` / `clear-night` (by `is_day`) |
| 2, 3, 45, 48 | `cloudy` |
| 51–67, 80–82 | `rain` |
| 71–77, 85, 86 | `snow` |
| 95, 96, 99 | `thunderstorm` |

### Moon phases

`clear-night` renders the moon with a real, phase-accurate terminator. The
phase is computed at swap time from the synodic cycle (29.53 days) and baked
into the shader as `#define MOON_PHASE` (∈ `[0,1)`: `0` new, `0.25` first
quarter, `0.5` full, `0.75` last quarter). Preview the whole cycle with
`ghostty-weather-moon-demo`.

## Technical notes

- **Why a new filename every swap.** Ghostty's renderer treats `custom-shader`
  changes by path; rotating the filename on each swap guarantees the reload is
  picked up rather than skipped, and keeps a previous shader file alive while
  another surface may still be compiling it (the cache keeps the 10 most
  recent).
- **Why baked `#define`s instead of uniforms.** Time-of-day and moon phase are
  injected as `#define`s because Ghostty does not expose a date/clock uniform
  (`iDate`) to custom shaders. Scenes guard each macro with `#ifndef`, so they
  also compile stand-alone.
- **Symlink-safe.** The commands resolve their own real path (following
  `~/.local/bin` symlinks with portable `readlink`), so the bundled scenes are
  found no matter how the command was invoked.

## Performance

These shaders run as a full-screen fragment pass every frame the terminal is
visible, so their cost is `pixels × refresh × per-pixel work`. The benchmark in
`bench/` measures each scene's GPU time and reports it as a percentage of the
display's per-frame budget (8.33 ms at 120 Hz), gating at a configurable
threshold (default **5%**).

```sh
bench/run-bench.sh            # build + benchmark all scenes at 3456×2234
```

Snapshot at 3456×2234 / 120 Hz on an M1 Max (% of the 8.33 ms frame budget):

| scene | % budget | | scene | % budget |
|---|---|---|---|---|
| clear-day | 2.2% | | snow | 3.2% |
| rain | 2.5% | | clear-night | 3.6% |
| thunderstorm | 3.1% | | cloudy | 4.6% |

All scenes are kept under 5% of a single frame. Three started well over and were
optimized down without changing their character: **clear-night** (23%→3.6%) now
evaluates its 3-octave moon-surface noise only inside the moon disk instead of
across the whole screen (lossless); **cloudy** (18%→4.6%) dropped from two
4-octave fbm passes to one inlined 2-octave pass with the shading cue derived
from the octaves it already has, gated to the sky band; **snow** (6%→3.2%) hashes
each cell once and moves the per-flake sway behind the density early-out. The
benchmark is the oracle for any future scene change.

`bench/glsl_bench.c` is a self-contained headless harness: it creates an
off-screen OpenGL 4.1 context via CGL (no window, no dependencies beyond macOS
system frameworks), wraps each scene in the same four uniforms Ghostty supplies
(`iResolution`, `iTime`, `iChannel0`, `iBackgroundColor`), and times steady-state
ms/frame over many trials. Additive blending across frames defeats the tile-GPU
dead-frame elimination that would otherwise collapse the timing to zero.

**Caveat:** macOS OpenGL is itself layered over Metal, so the absolute ms is a
proxy for Ghostty's native-Metal pipeline. Relative ranking between scenes and
the order-of-magnitude budget % are sound — which is what the gate needs.

Tunables are environment variables (`GHOSTTY_WEATHER_BENCH_W/_H`,
`GHOSTTY_WEATHER_REFRESH_HZ`, `GHOSTTY_WEATHER_BUDGET_PCT`); see the script
header. The dominant cost driver is procedural noise (fbm) evaluated per pixel,
so the levers that matter are **gating** it to where it is actually visible and
**reducing octaves / samples** — on Apple Silicon a cheaper *hash* does not help,
since the GPU's `sin()` is fast and a polynomial replacement measured slower.

## Cross-platform

The pipeline is macOS-first. The poller (`launchd`), battery awareness
(`pmset`), and compile-validation (`/usr/bin/log`) are macOS-specific; on Linux
the swap still applies and reloads, it just skips those steps. To use the
shaders on a Linux Ghostty host, run `./install.sh` (it targets
`~/.config/ghostty/config`) and drive scenes manually or from your own
scheduler.

## Uninstall

```sh
./install.sh --uninstall     # removes symlinks, the include, and the LaunchAgent
```

Runtime state under `~/.config/ghostty-weather/` and
`~/Library/Caches/ghostty-weather/` is left intact; delete it manually if you
want a clean slate.

## Layout

```
bin/
  ghostty-weather-swap        apply a scene + reload Ghostty
  ghostty-weather-poll        fetch weather, pick scene, swap; LaunchAgent installer
  ghostty-weather-toggle      pause / resume
  ghostty-weather-demo        cycle all scenes
  ghostty-weather-moon-demo   cycle lunar phases
shaders/scenes/               the six scene shaders (.glsl)
bench/
  glsl_bench.c                headless GPU timing harness (CGL/OpenGL)
  run-bench.sh                build + benchmark all scenes, gate on % budget
install.sh                    installer / uninstaller
```
