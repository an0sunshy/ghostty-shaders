#!/usr/bin/env bash
# install.sh — wire ghostty-shaders into your environment (idempotent).
#
#   ./install.sh                 link the command + add the Ghostty config include
#   ./install.sh --with-poller   ... and install the 5-min weather LaunchAgent
#   ./install.sh --uninstall     remove the link, the include, and the LaunchAgent
#
# What it does:
#   1. Migrates an existing `ghostty-weather` install in place (config/cache
#      dirs, log, LaunchAgent label, Ghostty include line, old symlinks) — see
#      migrate_from_ghostty_weather. Safe to re-run: a no-op once migrated.
#   2. Symlinks bin/ghostty-shaders into ~/.local/bin. The single dispatcher
#      resolves its real repo location *through* the symlink, so the bundled
#      scenes and libexec modules are still found.
#   3. Ensures Ghostty loads the generated active.conf via an absolute
#      `config-file = ?<...>/active.conf` line. On macOS this goes in the
#      always-loaded secondary config (~/Library/Application Support/...), so
#      it is independent of any dotfiles repo / branch. On Linux it goes in
#      ~/.config/ghostty/config.
#   4. (--with-poller) installs the launchd LaunchAgent that polls weather.

set -euo pipefail

REPO_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
BIN_SRC="$REPO_DIR/bin"
BIN_DST="$HOME/.local/bin"
GS="ghostty-shaders"
ACTIVE_FILE="$HOME/.config/ghostty-shaders/active.conf"
MARKER="# ghostty-shaders (managed by install.sh)"
INCLUDE_LINE="config-file = ?$ACTIVE_FILE"

# --- pre-rename install (ghostty-weather) — migration sources ----------------
OLD_CONFIG="$HOME/.config/ghostty-weather"
NEW_CONFIG="$HOME/.config/ghostty-shaders"
OLD_CACHE="$HOME/Library/Caches/ghostty-weather"
NEW_CACHE="$HOME/Library/Caches/ghostty-shaders"
OLD_LOG="$HOME/Library/Logs/ghostty-weather-poll.log"
NEW_LOG="$HOME/Library/Logs/ghostty-shaders-poll.log"
OLD_PLIST="$HOME/Library/LaunchAgents/dev.ghostty-weather.poll.plist"
OLD_INCLUDE_LINE="config-file = ?$OLD_CONFIG/active.conf"
OLD_MARKER="# ghostty-weather (managed by ~/dev/ghostty-weather)"
OLD_BINS=(ghostty-weather-swap ghostty-weather-poll ghostty-weather-toggle
          ghostty-weather-demo ghostty-weather-moon-demo)

ghostty_config_path() {
    case "$(uname -s)" in
        Darwin) echo "$HOME/Library/Application Support/com.mitchellh.ghostty/config" ;;
        *)      echo "${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config" ;;
    esac
}

# Strip a line (and its preceding marker comment) from the Ghostty config.
remove_include_line() {
    local gconf="$1" line="$2" marker="$3" tmp
    [ -f "$gconf" ] || return 0
    grep -qF "$line" "$gconf" || return 0
    tmp="$(mktemp)"
    grep -vF "$line" "$gconf" | grep -vF "$marker" > "$tmp"
    mv "$tmp" "$gconf"
}

# Move an existing ghostty-weather install to ghostty-shaders. Each step is
# guarded so re-running after migration (or a fresh install) is a clean no-op.
# Returns 0 and sets HAD_OLD_POLLER=1 if the old LaunchAgent was present, so
# the caller can re-enable the poller under the new label.
HAD_OLD_POLLER=0
migrate_from_ghostty_weather() {
    local migrated=0

    # Runtime state: move, don't delete (preserves location.json, config.env,
    # cache.json, last-scene, the pause markers, and rotated scene files).
    if [ -d "$OLD_CONFIG" ] && [ ! -d "$NEW_CONFIG" ]; then
        mv "$OLD_CONFIG" "$NEW_CONFIG"; migrated=1
    fi
    if [ -d "$OLD_CACHE" ] && [ ! -d "$NEW_CACHE" ]; then
        mv "$OLD_CACHE" "$NEW_CACHE"; migrated=1
    fi
    if [ -f "$OLD_LOG" ] && [ ! -f "$NEW_LOG" ]; then
        mv "$OLD_LOG" "$NEW_LOG"; migrated=1
    fi

    # The migrated active.conf still points custom-shader at a path under the
    # old cache dir; repoint it at the new one so the very next Ghostty reload
    # (before any fresh `apply`) still finds the rotated scene file.
    if [ -f "$NEW_CONFIG/active.conf" ] && grep -qF "$OLD_CACHE" "$NEW_CONFIG/active.conf"; then
        local tmp; tmp="$(mktemp)"
        sed "s#$OLD_CACHE#$NEW_CACHE#g" "$NEW_CONFIG/active.conf" > "$tmp"
        mv "$tmp" "$NEW_CONFIG/active.conf"
    fi

    # Old LaunchAgent: tear it down (the new label is installed separately).
    if [ -f "$OLD_PLIST" ]; then
        launchctl unload "$OLD_PLIST" 2>/dev/null || true
        rm -f "$OLD_PLIST"
        HAD_OLD_POLLER=1; migrated=1
    fi

    # Old Ghostty include line + marker.
    local gconf; gconf="$(ghostty_config_path)"
    if [ -f "$gconf" ] && grep -qF "$OLD_INCLUDE_LINE" "$gconf"; then
        remove_include_line "$gconf" "$OLD_INCLUDE_LINE" "$OLD_MARKER"; migrated=1
    fi

    # Old command symlinks.
    local b link
    for b in "${OLD_BINS[@]}"; do
        link="$BIN_DST/$b"
        if [ -L "$link" ]; then rm -f "$link"; migrated=1; fi
    done

    [ "$migrated" -eq 1 ] && echo "→ migrated existing ghostty-weather install to ghostty-shaders"
    return 0
}

cmd_install() {
    # Migrate FIRST, before creating the new config dir — the migration moves
    # ~/.config/ghostty-weather → ~/.config/ghostty-shaders and is guarded on
    # the new dir not existing yet, so pre-creating it would silently skip the
    # move and lose the user's location config.
    migrate_from_ghostty_weather

    mkdir -p "$BIN_DST" "$(dirname "$ACTIVE_FILE")"

    echo "→ linking command into $BIN_DST"
    ln -sf "$BIN_SRC/$GS" "$BIN_DST/$GS"
    echo "    $GS"

    local gconf; gconf="$(ghostty_config_path)"
    mkdir -p "$(dirname "$gconf")"; touch "$gconf"
    if grep -qF "$INCLUDE_LINE" "$gconf"; then
        echo "→ Ghostty include already present in $gconf"
    else
        printf '\n%s\n%s\n' "$MARKER" "$INCLUDE_LINE" >> "$gconf"
        echo "→ added Ghostty include to $gconf"
    fi

    case ":$PATH:" in
        *":$BIN_DST:"*) ;;
        *) echo "⚠  $BIN_DST is not on your PATH — add it to your shell rc." ;;
    esac

    # Re-enable the weather poller under the new label when --with-poller is
    # given, OR when migration just removed an already-running old poller (so a
    # user who had auto-updates keeps them without re-opting-in).
    if [ "${1:-}" = "--with-poller" ] || [ "$HAD_OLD_POLLER" -eq 1 ]; then
        echo "→ installing weather poller (LaunchAgent)"
        "$BIN_DST/$GS" weather on
    fi

    echo
    echo "✓ installed. Next:"
    echo "    ghostty-shaders weather set-city \"Seattle, WA\"   # set your location"
    echo "    ghostty-shaders apply clear-night                 # try a scene now"
    echo "    ghostty-shaders weather on                        # enable 5-min auto-updates"
}

cmd_uninstall() {
    echo "→ removing command symlink from $BIN_DST"
    [ -L "$BIN_DST/$GS" ] && { rm -f "$BIN_DST/$GS"; echo "    removed $GS"; }
    # Sweep any leftover pre-rename symlinks too.
    local b
    for b in "${OLD_BINS[@]}"; do
        [ -L "$BIN_DST/$b" ] && { rm -f "$BIN_DST/$b"; echo "    removed $b (legacy)"; }
    done

    echo "→ removing LaunchAgent (if installed)"
    "$BIN_SRC/$GS" weather off 2>/dev/null || true
    [ -f "$OLD_PLIST" ] && { launchctl unload "$OLD_PLIST" 2>/dev/null || true; rm -f "$OLD_PLIST"; }

    local gconf; gconf="$(ghostty_config_path)"
    remove_include_line "$gconf" "$INCLUDE_LINE" "$MARKER"
    remove_include_line "$gconf" "$OLD_INCLUDE_LINE" "$OLD_MARKER"
    echo "→ removed Ghostty include from $gconf"
    echo "✓ uninstalled. Runtime state under ~/.config/ghostty-shaders and"
    echo "  ~/Library/Caches/ghostty-shaders left intact; remove manually if desired."
}

case "${1:-}" in
    --uninstall)   cmd_uninstall ;;
    --with-poller) cmd_install --with-poller ;;
    "")            cmd_install ;;
    *)             echo "usage: $0 [--with-poller|--uninstall]" >&2; exit 1 ;;
esac
