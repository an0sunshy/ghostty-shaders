# What & why

<!-- What does this change do, and why? Link any related issue. -->

## Scenes touched

<!-- List affected scenes, or "none" if this is non-scene work. -->

## Checklist

- [ ] `bench/run-bench.sh` passes — all scenes under 5% of the frame budget
- [ ] `bench/golden.sh check` passes, or golden references were updated and committed
- [ ] `shellcheck` is clean for any changed bash (`bin/`, `install.sh`, `bench/*.sh`, `scripts/`)
- [ ] Works on macOS Ghostty **and** Linux Ghostty (or the macOS-only scope is called out)
- [ ] Docs / CHANGELOG updated if behavior or usage changed
- [ ] Kept in **draft** until ready for review
