# ghostty-shaders

![CI](https://github.com/an0sunshy/ghostty-shaders/actions/workflows/ci.yml/badge.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)

Animated **classical Chinese poem** background shaders for the
[Ghostty](https://ghostty.org) terminal — 24 scenes evoking the 意境 of poems
like 靜夜思, 春江花月夜, and 江雪.

A small daemon **matches a poem to your live conditions** every 5 minutes —
local weather, time of day, season, and proximity to a festival — and hot-swaps
Ghostty's `custom-shader`, reloading every open window in place, no restart. Or
pin one and keep it (`ghostty-shaders use <scene>`). Text stays fully legible:
every scene renders **behind** the terminal contents and lets the glyph layer
pass through untouched.

**[Live demo →](https://an0sunshy.github.io/ghostty-shaders/)** — every scene
running in your browser, with the per-poem feeling dials as live sliders. The
gallery compiles the **exact** `.glsl` files Ghostty runs, wrapped in a short
WebGL2 preamble — scenes are written in the
[portable GLSL subset](docs/shader-portability.md) and CI validates every one
under both the desktop GL and WebGL2 profiles.

## The collection

[![the poem collection](docs/poc-poetry/contact-all.png)](https://an0sunshy.github.io/ghostty-shaders/)

Twenty-four scenes, each a luminous-on-dark composition built on 留白 (negative
space) so the centre stays open for legible text. Full list and authoring notes:
[docs/poc-poetry.md](docs/poc-poetry.md).

## How it works

```text
 ┌─ select --cron (5 min) ──┐   ┌─ rule engine ──────┐   ┌─ apply ──────┐   ┌ Ghostty ┐
 │ providers → facts:       │   │ score every poem   │   │ bake #defines│   │ reload   │
 │  weather · time · season │──▶│ against its tags,  │──▶│ write active │──▶│ recompile│
 │  · festival proximity    │   │ then weighted-pick │   │ kill -USR2   │   │ shader   │
 └──────────────────────────┘   └────────────────────┘   └──────────────┘   └──────────┘
```

1. **Providers** (`libexec/ghostty-shaders/providers/`) each emit JSON *facts*:
   live weather from [Open-Meteo](https://open-meteo.com/) (free, no API key),
   the time-of-day phase, the season (from date + latitude), and the nearest
   festival. Offline or a failed provider just drops that fact.
2. **The rule engine** scores every poem: declarative rules
   (`collections/poems.rules.json`) map facts to weighted tags, each scene
   declares what it *is* (`collections/poems.index.json`), and the score is the
   overlap. A temperature-controlled **weighted-random** pick adds variety, with
   a recency penalty so it doesn't repeat.
3. **`apply`** copies the chosen scene to a fresh file under
   `~/Library/Caches/ghostty-shaders/`, bakes the feeling dials in as
   `#define`s, and points `active.conf` at it.
4. **Ghostty** reloads on `SIGUSR2` and recompiles for every open surface — the
   new scene appears within a frame.

If a scene fails to compile, the swap catches it in Ghostty's log and reverts to
the previous one, so a bad edit never leaves you shaderless.

## Requirements

- **Ghostty** with `SIGUSR2` config-reload support (tested on 1.3.1).
- **macOS** for the automatic poller (`launchd`) and the compile-validation
  step (`/usr/bin/log`). The shaders and the manual `apply`/`toggle`/`demo`
  subcommands work on Linux Ghostty too — see [Cross-platform](#cross-platform).
- `curl` for weather + geocoding. **`jq`** powers the matcher's rule engine; if
  it's absent the poller degrades to a simple time-of-day pick (and says so).

## Install

```sh
git clone https://github.com/an0sunshy/ghostty-shaders.git ~/dev/ghostty-shaders
cd ~/dev/ghostty-shaders
./install.sh                 # links the command + wires the Ghostty include
# or, in one shot, also start the auto-poller:
./install.sh --with-poller
```

`install.sh` symlinks the `ghostty-shaders` command into `~/.local/bin` and adds an absolute
`config-file = ?…/active.conf` line to Ghostty's always-loaded secondary
config (`~/Library/Application Support/com.mitchellh.ghostty/config` on macOS),
so it works regardless of how your main config is managed.

## Usage

**Auto** — let the poller match a poem to live conditions:

```sh
ghostty-shaders select                # match once now and apply
ghostty-shaders select --print        # dry-run: show the pick (and why) — applies nothing
ghostty-shaders weather on            # install the 5-min auto-poller
ghostty-shaders weather off           # remove it
```

The poller runs every **5 minutes** by default; to change it, set the interval
(in seconds) when you enable it:
`GHOSTTY_SHADERS_POLL_INTERVAL=600 ghostty-shaders weather on`.

**Static** — pin a scene and keep it:

```sh
ghostty-shaders list poems            # the scene names in the collection
ghostty-shaders use jing-ye-si        # pin one scene and keep it
ghostty-shaders random poems          # pin a random scene from the collection
```

While a scene is pinned with `use`/`random`, the cron poller stands down so it
won't clobber your pick; `ghostty-shaders select` (or `weather on`) returns you
to auto mode. Per-new-window random rotation is
[deferred](docs/random-per-window.md). Other commands:

```sh
ghostty-shaders apply jing-ye-si      # apply a scene once, without pinning it
ghostty-shaders toggle                # pause / resume the active shader
ghostty-shaders toggle --status       # show current scene / paused state
ghostty-shaders demo [seconds]        # cycle the poem scenes for a visual review
```

## Configuration

Location and behavior live in `~/.config/ghostty-shaders/config.env`:

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
ghostty-shaders weather set-city "Seattle, WA"
```

Direct `LAT`/`LON` make **zero** third-party calls. A city/ZIP is geocoded a
single time and cached in `location.json`; subsequent polls reuse it. Latitude
also drives the season fact, so the southern hemisphere is matched correctly.

### Poem feeling dials

Each poem scene reads four "feeling" dials so you can tune its 意境 without
touching the shader. Set them as env vars when you pin a scene — they bake into
the applied shader — and every dial defaults to the scene's authored look:

```sh
GHOSTTY_SHADERS_MOOD=-1      # cold/blue ‹0› warm/tender    (-1 … 1)
GHOSTTY_SHADERS_ENERGY=1.4   # still ‹1› lively (motion)    (0.3 … 2)
GHOSTTY_SHADERS_DENSITY=0.6  # sparse 留白 ‹1› lush (fill)   (0.3 … 1.8)
GHOSTTY_SHADERS_GLOW=1.8     # crisp ‹1› dreamy (bloom)     (0.6 … 2.5)
ghostty-shaders use jiang-xue
```

The [live gallery](https://an0sunshy.github.io/ghostty-shaders/) exposes the
same four as live sliders for any poem.

### Tuning the matcher

The matcher is data, not code — edit and re-run, no rebuild:

- **`collections/poems.index.json`** — each scene's affinity tags (season, time,
  weather, festival, geography, mood). Adding a scene is one row here.
- **`collections/poems.rules.json`** — declarative `when → boost/veto` rules
  mapping live facts to tag weights.
- **`data/festivals.json`** — precomputed Gregorian dates for the festivals the
  matcher knows (Mid-Autumn, Qingming, Double Seventh, Double Ninth).
- **`collections/poems.conf`** — `selection_temperature` (0 = always the top
  match; higher = more variety) and the recency window.

Adding a new input is a new file in `providers/` that prints a JSON fact — the
engine needs no change. `ghostty-shaders select --print` shows the merged facts
and the top-scoring scenes, so you can see exactly why a poem was chosen.

## Technical notes

- **Why a new filename every swap.** Ghostty's renderer treats `custom-shader`
  changes by path; rotating the filename on each swap guarantees the reload is
  picked up rather than skipped, and keeps a previous shader file alive while
  another surface may still be compiling it (the cache keeps the 10 most
  recent).
- **Why baked `#define`s instead of uniforms.** The feeling dials are injected
  as `#define`s because Ghostty does not expose a date/clock uniform (`iDate`)
  to custom shaders. Scenes guard each macro with `#ifndef`, so they also
  compile stand-alone.
- **Symlink-safe.** The commands resolve their own real path (following
  `~/.local/bin` symlinks with portable `readlink`), so the bundled scenes are
  found no matter how the command was invoked.

## Performance

These shaders run a full-screen fragment pass every frame the terminal is
visible, so the gate is GPU time as a percentage of the display's per-frame
budget (8.33 ms at 120 Hz). Poems are opt-in art a user selects (not an
always-on default), so the collection carries a **75%** per-frame ceiling,
enforced by `bench/run-bench.sh`; every shipped scene sits comfortably under it.

```sh
bench/run-bench.sh            # build + benchmark all scenes at 3456×2234
```

The headless harness, the OpenGL-over-Metal caveat, and how to tune a scene are
documented in **[docs/performance.md](docs/performance.md)**.

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

Runtime state under `~/.config/ghostty-shaders/` and
`~/Library/Caches/ghostty-shaders/` is left intact; delete it manually if you
want a clean slate.

## Contributing & quality

Contributions are welcome — new scenes especially. Start with
[`CONTRIBUTING.md`](CONTRIBUTING.md) for dev setup and the
[`docs/scene-authoring.md`](docs/scene-authoring.md) guide for the uniform list,
baked `#define`s, and the legibility-and-performance conventions every scene
must follow. Two gates are non-negotiable: the **compute gate**
(`bench/run-bench.sh`, every scene under its collection's budget) and the
**golden-image** check. The decision logic (the matcher's providers, rule
engine, and weighted pick, plus config parsing) is unit-tested by
`tests/run-tests.sh`, which runs in CI on Linux. Beyond CI, the repo keeps a
panel of review personas — reproducible Claude Code reviewers that judge what CI
can't.

- [`CONTRIBUTING.md`](CONTRIBUTING.md) — dev setup, adding a scene, commit style
- [`docs/scene-authoring.md`](docs/scene-authoring.md) — shader conventions
- [`docs/performance.md`](docs/performance.md) — the compute gate, harness, and tuning
- [`bench/run-bench.sh`](bench/run-bench.sh) — the compute gate (see [Performance](#performance))
- [`docs/review-personas.md`](docs/review-personas.md) — the review panel

## License

MIT — see [LICENSE](LICENSE).

## Layout

```text
bin/          the single `ghostty-shaders` dispatcher (the only command on PATH)
libexec/      subcommand implementations (apply, select, weather, toggle, demo) + providers/
shaders/      scene shaders (poems/) + portable GLSL helpers
collections/  per-collection metadata: display titles, the matcher index + rules, knobs
data/         precomputed festival dates for the matcher
web/          the WebGL2 scene gallery (the GitHub Pages demo)
bench/        headless GPU timing + golden-image harness (the compute gate)
scripts/      scene discovery + process helpers, gallery build / serve, asset capture
tests/        unit tests for the decision logic + install migration (CI: ubuntu)
docs/         scene authoring, shader portability, performance, review panel
```

Full file-by-file tree: [CONTRIBUTING.md → Repo layout](CONTRIBUTING.md#repo-layout).
