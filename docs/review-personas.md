# Review personas

ghostty-weather ships a small panel of **review personas** — Claude Code
subagents under [`.claude/agents/`](../.claude/agents/), each a sharp,
single-responsibility reviewer with its own charter. They exist so the quality
bar is *reproducible and shareable* instead of living in one maintainer's head:
the same six lenses run against every release and every non-trivial PR, in the
repo, versioned alongside the code they judge.

This is the human/agent half of the quality system. The mechanical half lives in
CI ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)); the two are
designed to complement, not duplicate, each other — see
[What's mechanized vs adjudicated](#whats-mechanized-vs-adjudicated).

## Why personas instead of ad-hoc review

- **Reproducible.** A persona is a written charter, not a mood. The same checks
  fire every time, so a clean pass means the same thing in June as in December.
- **Shareable.** Contributors can run the exact reviewers the maintainer uses
  before they open a PR, and read the charters to learn what "good" means here.
- **Single-responsibility.** Each persona owns one concern and names the
  concrete files it inspects, so findings are specific to this repo (e.g. "the
  `iChannel0` passthrough in `snow.glsl`"), not generic lint.
- **Composable.** Run one when you touch one area; fan out the whole panel for a
  release.

## The roster

| Persona | Owns | What it flags here |
|---|---|---|
| [`oss-maintainer`](../.claude/agents/oss-maintainer.md) | Star-worthiness & contribution friction | Missing/placeholder hero visual, absent LICENSE/CONTRIBUTING/CoC/SECURITY, issue & PR templates, scene-name drift across README ↔ `pick_scene()` ↔ `shaders/scenes/`, CHANGELOG/semver hygiene |
| [`end-user-advocate`](../.claude/agents/end-user-advocate.md) | Install / upgrade / uninstall UX | `./install.sh` on a clean Mac, the `git pull` upgrade story, no-`jq` / no-network / on-battery behavior, compile-failure auto-revert, clarity of error messages, `toggle`/`--status` |
| [`security-reviewer`](../.claude/agents/security-reviewer.md) | Threat model of the bash + install footprint | Command injection / unquoted expansions, `curl` usage, the LaunchAgent plist & `config-file` include, `SIGUSR2` targeting, location privacy (direct LAT/LON = zero 3P calls), no secrets in logs — cross-checked against [`SECURITY.md`](../SECURITY.md) |
| [`perf-gpu-engineer`](../.claude/agents/perf-gpu-engineer.md) | The compute gate & benchmark fidelity | Any scene over 5% of the 8.33 ms/120 Hz budget, un-gated per-pixel fbm, octave creep, regressions vs `bench/baseline.json`, the Metal-vs-OpenGL proxy caveat, the Apple-Silicon "cheaper hash doesn't help" trap |
| [`accessibility-legibility`](../.claude/agents/accessibility-legibility.md) | The core promise: text stays legible | Intact `iChannel0` alpha-composite passthrough in every scene, glyph contrast over the effect, `IS_DAY` night dimming, motion/flash intensity (reduced-motion analog), colorblind safety, light-background terminals |
| [`visual-regression-qa`](../.claude/agents/visual-regression-qa.md) | `bench/golden.sh` | A golden reference for every scene, meaningful diff tolerance, every scene change updating or passing golden, deterministic inputs (fixed `iTime`, transparent `iChannel0`), the cross-hardware fp-determinism caveat |

## How to run them with Claude Code

**One reviewer, one area.** When a change touches a single concern, invoke that
persona directly — through the Task tool, or in plain language:

> use the perf-gpu-engineer subagent to review the cloudy.glsl change
>> use the accessibility-legibility subagent on shaders/scenes/snow.glsl

The subagent reads only what its charter names, runs the relevant commands
(`bench/run-bench.sh`, `shellcheck`, `glslangValidator`, `bench/golden.sh check`),
and returns findings in the shared `{severity, location, finding, suggested fix}`
format.

**The whole panel, for a release or a broad PR.** Fan all six out and synthesize
their findings into one report. The **Workflow tool** is the right way to do this
— it runs the personas concurrently and merges their outputs, so a release review
is a single fan-out/fan-in pass rather than six sequential conversations. (This
doc describes the pattern; it deliberately does not ship an executable workflow
script — the panel is the six charters, and how you orchestrate them is up to the
caller.)

A practical release pass:

1. Fan out all six personas against the release diff.
2. Collect findings, deduplicate, and sort by severity
   (`blocker` > `major` > `minor` > `nit`).
3. Resolve every `blocker` and `major` before tagging; triage the rest into
   `CHANGELOG.md` / issues.

## What's mechanized vs adjudicated

Some of what the personas care about is already enforced by CI on every push and
PR — the personas should *rely* on those gates rather than re-deriving them, and
spend their attention on the judgment calls CI cannot make.

**Mechanized in CI** (`.github/workflows/ci.yml`):

- **Compute gate** — `bench/run-bench.sh` fails the macOS job if any scene
  exceeds 5% of the frame budget. (`perf-gpu-engineer`'s hard floor.)
- **Golden-image diff** — `bench/golden.sh check` fails on visual drift beyond
  tolerance. (`visual-regression-qa`'s hard floor.)
- **Shellcheck** — every `bin/` script, `install.sh`, and `bench/*.sh` on Linux.
  (`security-reviewer` / `end-user-advocate` baseline.)
- **GLSL parse** — `glslangValidator` on each scene wrapped by
  `bench/wrap-shader.sh`.
- **Markdown lint** — `markdownlint-cli2` across all docs.

**Needs human/agent adjudication** (what the panel is *for*):

- Whether the README's first screen actually *sells* the project, and whether a
  real screenshot/GIF exists (CI can't judge "compelling").
- Whether an error message is *recoverable* — names the file to edit and the
  command to run.
- Whether a shader still washes out text at peak brightness, even if it passes
  the golden diff at the pinned `iTime`.
- Whether a "perf optimization" preserved the scene's *character* or just its
  timing, and whether it fell into the cheaper-hash trap.
- Whether attacker-influenced data (a crafted city name, a hostile Open-Meteo
  response) could ever reach the shell as code.
- Whether the contribution on-ramp is genuinely low-friction.

The rule of thumb: **if CI can decide it, let CI decide it; the personas judge
everything CI can't.**

## Adding a persona

1. Add `.claude/agents/<kebab-name>.md` with the standard frontmatter
   (`name`, `description`, `tools: Read, Grep, Glob, Bash`) and a charter body:
   a one-line mission, a "What you inspect here" list naming concrete files, a
   focused checklist, and the shared
   `{severity, location, finding, suggested fix}` output format. Keep it
   ~40–70 lines and specific to this repo.
2. Add a row to [the roster](#the-roster) above.
3. If the new concern has a mechanizable floor, wire it into
   `.github/workflows/ci.yml` so the persona can lean on the gate and focus on
   judgment.
