#!/usr/bin/env bash
# ghostty-process.sh — locate the running Ghostty terminal and signal it to
# hot-reload its config. Shared by the `apply` and `toggle` subcommands so the
# (subtle, regression-prone) process matcher lives in exactly one place.
#
# This file only defines functions (no side effects), so it is safe to source
# under `set -euo pipefail`.

# PIDs from `ps -o pid=,comm=` lines (on stdin) whose comm basename is exactly
# `ghostty`. Split out as a pure filter — the matcher is the part that subtly
# breaks, so it is unit-tested in tests/run-tests.sh against realistic ps
# output (full app path, bare name, helper exclusion). NOTE: `ps`
# right-justifies the pid column, so each line starts with leading spaces — the
# `^[[:space:]]*` is load-bearing; without it a bare-comm `ghostty` (CLI/Linux
# launch) is never matched.
ghostty_pids_from_ps() {
    awk '{ pid=$1; sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "")
           n=split($0, a, "/"); if (a[n] == "ghostty") print pid }'
}

# PIDs of the running Ghostty terminal, owned by the current user. NOT
# `pgrep -x ghostty`: when Ghostty is launched from the .app bundle (the normal
# case on macOS) its accounting name is the full executable path, which pgrep
# truncates to 16 chars (`/Applications/Gh…`), so `-x ghostty` never matches.
# Parsing `ps -o comm` and matching the exact basename works whether comm is
# the full path or a bare `ghostty`. Trailing `|| true`: a `ps`/`awk` failure
# must not abort the caller under `set -e` + pipefail.
ghostty_pids() { ps -axo pid=,comm= -U "$(id -u)" | ghostty_pids_from_ps || true; }

# Send SIGUSR2 to every Ghostty process owned by the current user — Ghostty's
# macOS AppDelegate installs a handler that calls reloadConfig(). No-op (not an
# error) when Ghostty isn't running.
ghostty_signal() {
    local pids
    pids=$(ghostty_pids)
    # Guard with an explicit `if`, not `[[ -n $pids ]] && kill …`: when no
    # Ghostty is running the && short-circuit returns non-zero, which under
    # `set -e` would abort the caller before its next step.
    if [[ -n $pids ]]; then
        # shellcheck disable=SC2086  # multi-PID list; word-splitting is intended
        kill -USR2 $pids
    fi
}
