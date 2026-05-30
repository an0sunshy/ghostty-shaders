#!/usr/bin/env bash
# install.sh — wire ghostty-weather into your environment (idempotent).
#
#   ./install.sh                 link commands + add the Ghostty config include
#   ./install.sh --with-poller   ... and install the 15-min weather LaunchAgent
#   ./install.sh --uninstall     remove links, the include, and the LaunchAgent
#
# What it does:
#   1. Symlinks bin/ghostty-weather-* into ~/.local/bin. The scripts resolve
#      their real repo location *through* the symlink, so the bundled scenes
#      are still found.
#   2. Ensures Ghostty loads the generated active.conf via an absolute
#      `config-file = ?<...>/active.conf` line. On macOS this goes in the
#      always-loaded secondary config (~/Library/Application Support/...), so
#      it is independent of any dotfiles repo / branch. On Linux it goes in
#      ~/.config/ghostty/config.
#   3. (--with-poller) installs the launchd LaunchAgent that polls weather.

set -euo pipefail

REPO_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
BIN_SRC="$REPO_DIR/bin"
BIN_DST="$HOME/.local/bin"
ACTIVE_FILE="$HOME/.config/ghostty-weather/active.conf"
MARKER="# ghostty-weather (managed by ~/dev/ghostty-weather)"
INCLUDE_LINE="config-file = ?$ACTIVE_FILE"

ghostty_config_path() {
    case "$(uname -s)" in
        Darwin) echo "$HOME/Library/Application Support/com.mitchellh.ghostty/config" ;;
        *)      echo "${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config" ;;
    esac
}

cmd_install() {
    mkdir -p "$BIN_DST" "$(dirname "$ACTIVE_FILE")"

    echo "→ linking commands into $BIN_DST"
    for f in "$BIN_SRC"/ghostty-weather-*; do
        ln -sf "$f" "$BIN_DST/$(basename "$f")"
        echo "    $(basename "$f")"
    done

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

    if [ "${1:-}" = "--with-poller" ]; then
        echo "→ installing weather poller (LaunchAgent)"
        "$BIN_DST/ghostty-weather-poll" --install
    fi

    echo
    echo "✓ installed. Next:"
    echo "    ghostty-weather-poll --set-city \"Seattle, WA\"   # set your location"
    echo "    ghostty-weather-swap clear-night                 # try a scene now"
    echo "    ghostty-weather-poll --install                   # enable 15-min auto-updates"
}

cmd_uninstall() {
    echo "→ removing command symlinks from $BIN_DST"
    for f in "$BIN_SRC"/ghostty-weather-*; do
        local link="$BIN_DST/$(basename "$f")"
        if [ -L "$link" ]; then rm -f "$link"; echo "    removed $(basename "$f")"; fi
    done

    echo "→ removing LaunchAgent (if installed)"
    "$BIN_SRC/ghostty-weather-poll" --uninstall 2>/dev/null || true

    local gconf; gconf="$(ghostty_config_path)"
    if [ -f "$gconf" ] && grep -qF "$INCLUDE_LINE" "$gconf"; then
        local tmp; tmp="$(mktemp)"
        grep -vF "$INCLUDE_LINE" "$gconf" | grep -vF "$MARKER" > "$tmp"
        mv "$tmp" "$gconf"
        echo "→ removed Ghostty include from $gconf"
    fi
    echo "✓ uninstalled. Runtime state under ~/.config/ghostty-weather and"
    echo "  ~/Library/Caches/ghostty-weather left intact; remove manually if desired."
}

case "${1:-}" in
    --uninstall)   cmd_uninstall ;;
    --with-poller) cmd_install --with-poller ;;
    "")            cmd_install ;;
    *)             echo "usage: $0 [--with-poller|--uninstall]" >&2; exit 1 ;;
esac
