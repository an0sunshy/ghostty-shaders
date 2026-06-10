# Publishing checklist

Maintainer runbook for taking this repo from local-only to public, and for
cutting releases after that. Everything here is a one-time or
per-release manual step — day-to-day quality gates live in CI.

## One-time: first publication

1. **Pick the canonical handle.** `CHANGELOG.md`'s compare links already
   use `an0sunshy`; the placeholders elsewhere say `OWNER`. Unify on one:

   ```sh
   grep -rln 'OWNER' README.md web/index.html .github/ISSUE_TEMPLATE/config.yml
   # replace OWNER with the real org/user in those three files,
   # and confirm the CHANGELOG links point at the same owner
   ```

2. **Screenshots.** `assets/` ships scene renders from the golden pipeline;
   replace them over time with real terminal captures (PNG) and a short GIF
   of a live swap — the README calls this out to contributors too.

3. **Create the repo and push** (public, empty — no auto-README):

   ```sh
   gh repo create <owner>/ghostty-weather --public --source . --push
   ```

4. **Repository settings:**
   - Description + topics (`ghostty`, `glsl`, `shaders`, `terminal`,
     `weather`), social-preview image (a scene capture).
   - **Discussions: enable** — `.github/ISSUE_TEMPLATE/config.yml` links to
     it.
   - **Pages: Source = "GitHub Actions"** — required by
     `.github/workflows/pages.yml`; the gallery deploys on the first push
     to `main` after that.
   - Branch protection on `main`: require the CI checks
     (`Lint`, `Unit tests`, `Compute gate`) and pull requests before merge.

5. **Watch the first CI run — calibration expected.** The compute gate and
   golden-image check have only ever run on the maintainer's M1 Max;
   GitHub's `macos-14` runner is a VM with different GPU behavior.
   - If the **compute gate** fails or is noisy: raise the CI budget via
     `GHOSTTY_WEATHER_BUDGET_PCT` in `ci.yml` (the local 5% gate on real
     hardware remains the contract; the CI number is a regression tripwire,
     not the spec). Record whatever the runner measures as its own
     baseline.
   - If the **golden check** drifts with unchanged shaders: that's GPU
     variance, not regression — bump `GHOSTTY_WEATHER_GOLDEN_TOLERANCE`
     for CI per the policy in `bench/golden.sh`'s header. Do NOT
     regenerate the committed goldens on a CI runner.

6. **Tag and release v0.1.0:**

   ```sh
   git tag -a v0.1.0 -m "ghostty-weather v0.1.0"
   git push origin v0.1.0
   gh release create v0.1.0 --title "v0.1.0" \
     --notes-file <(sed -n '/^## \[0.1.0\]/,/^## \[/p' CHANGELOG.md | sed '$d')
   ```

## Per release, after that

1. Move `## [Unreleased]` content in `CHANGELOG.md` into a new dated
   version section; add fresh compare links at the bottom.
2. Bump, tag, push, `gh release create` as above.
3. Sanity-check the live Pages gallery after the deploy completes — it
   re-deploys automatically on any `main` push touching `web/` or
   `shaders/`.

## Standing automation

- **CI** (`ci.yml`): shellcheck, dual-profile GLSL validation, markdown
  lint, unit tests (ubuntu), compute gate + golden image (macos).
- **Pages** (`pages.yml`): deploys the gallery from `main`.
- **Dependabot** (`dependabot.yml`): monthly grouped PRs for action
  version bumps — the only dependency surface this project has.
