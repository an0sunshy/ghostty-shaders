# Deferred: per-new-window random rotation

`ghostty-shaders random` today is a **one-shot**: it pins one random scene and
applies it. The originally-requested behavior — *each new terminal window picks
a fresh random scene* — is **not yet wired**. This note records why, and the
shape it would take, so it can be picked up later.

## Why it isn't wired yet

Ghostty's `custom-shader` is a **global** setting: one shader for every open
surface, swapped by rewriting `active.conf` and signalling `SIGUSR2`. There is
no per-window shader. So "a new scene per new window" cannot be a window-scoped
shader; it has to be a **hook that re-randomizes the global scene whenever a new
shell starts**, accepting that the change is visible in all windows at once.

That trade-off (a new window restyles every window) is worth a deliberate design
pass rather than shipping it implicitly, so it is deferred. Static selection
(`use` / one-shot `random`) covers the "pick one and keep it" case now.

## The shape it would take

A shell hook that runs on each new interactive shell:

```sh
# ~/.zshrc / ~/.bashrc — opt-in
command -v ghostty-shaders >/dev/null && ghostty-shaders random poems >/dev/null 2>&1
```

To make this a first-class feature rather than a dotfiles snippet, it would want:

- An **opt-in install step** (e.g. `ghostty-shaders random --per-window install`)
  that adds the hook to the user's shell rc behind a clear marker, and a matching
  uninstall — mirroring how `install.sh` manages the Ghostty include line.
- **Debounce / cooldown** so a burst of new shells (a tmux/Cmd-T spree) doesn't
  trigger a rerender storm. The existing rotation lock in `apply` already
  serializes writes, but the hook should also rate-limit itself (skip if the last
  random swap was < N seconds ago).
- A **mode interaction** decision: per-window random is mutually exclusive with
  the weather poller and with a fixed `use` pin. Installing it should set the
  selection mode accordingly (and the cron poller should stand down, exactly as
  it does for a static pin today via the `selection` marker).

None of this is implemented; `ghostty-shaders random` remains one-shot until it
is. `ghostty-shaders list` and `--help` describe only the shipped behavior.
