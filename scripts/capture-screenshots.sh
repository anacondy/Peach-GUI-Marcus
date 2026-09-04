#!/usr/bin/env bash
# scripts/capture-screenshots.sh
#
# Captures the README screenshots ON A RUNNING MARCUS MIX SESSION, with grim.
#
# Read this before you expect anything from it: it cannot run in a CI container
# or on a build host. grim needs a live Wayland socket and a compositor that
# implements the wlr-screencopy protocol, and it has to run as a client of the
# session you want pictures of. Run it from a kitty window inside the desktop.
#
#   ./scripts/capture-screenshots.sh            # capture into docs/screenshots/
#   ./scripts/capture-screenshots.sh --list     # show outputs grim can see
#
# The filenames it produces are the exact ones README.md links to, so running it
# replaces the rendered previews with real captures and nothing else changes.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="${REPO_ROOT}/docs/screenshots"

if [[ "${1:-}" == "--list" ]]; then
    exec swaymsg -t get_outputs -r | jq -r '.[] | select(.active) | "\(.name): \(.current_mode.width)x\(.current_mode.height)@\((.current_mode.refresh/1000)|round)Hz scale \(.scale)"'
fi

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    echo "capture-screenshots: WAYLAND_DISPLAY is unset — run this from inside a Marcus Mix session, not from a tty or a build host." >&2
    exit 1
fi
for b in grim slurp swaymsg; do
    command -v "$b" >/dev/null 2>&1 || { echo "capture-screenshots: $b not found (should be in packages.x86_64)" >&2; exit 1; }
done

mkdir -p "$OUT_DIR"

# Let the shell settle: any transient notification or window that appeared when
# you launched this would otherwise be baked into every shot.
sleep 1

shot() {
    local name="$1"; shift
    grim "$@" "${OUT_DIR}/${name}.png"
    echo "capture-screenshots: ${name}.png"
}

# 1. The desktop as it sits: top bar, dock, wallpaper, nothing open.
#    This is the money shot — it shows the whole environment in one frame.
swaymsg 'workspace 1' >/dev/null
sleep 0.6
shot 01-desktop

# 2. A real workspace in use: terminal with fastfetch (which proves the live
#    hardware query works) next to the file manager.
swaymsg 'exec kitty -e sh -c "fastfetch; exec zsh"' >/dev/null
sleep 2.5
swaymsg 'split horizontal' >/dev/null
swaymsg 'exec pcmanfm' >/dev/null
sleep 2.5
shot 02-terminal-and-files

# 3. The Spotlight launcher, which is the interaction people most want to see.
#    It has to be driven by the real keybinding path so the screenshot shows the
#    actual thing rather than a wofi started by hand with different arguments.
swaymsg 'workspace 2' >/dev/null
sleep 0.4
"$HOME/.config/sway/scripts/spotlight.sh" &
sleep 2
shot 03-spotlight
pkill -x wofi 2>/dev/null || true

# 4. Close-up of the top bar, so the IST clock and the module icons are legible
#    at README scale.
BAR_RECT="$(swaymsg -t get_tree -r | jq -r '
    [.. | objects | select(.type == "floating_con") | .. | objects
     | select(.app_id? == "waybar" or .name? == "waybar")] | .[0].rect
     | "\(.x),\(.y) \(.width)x\(.height)"' 2>/dev/null || true)"
if [[ -n "${BAR_RECT:-}" ]]; then
    grim -g "$BAR_RECT" "${OUT_DIR}/04-topbar.png"
    echo "capture-screenshots: 04-topbar.png"
else
    # The tree walk can miss layer-shell surfaces depending on sway version;
    # fall back to a fixed strip that contains the 28px bar.
    grim -g "0,0 $(swaymsg -t get_outputs -r | jq -r '.[0] | "\(.rect.width)x120"') \
        " "${OUT_DIR}/04-topbar.png"
    echo "capture-screenshots: 04-topbar.png (fixed strip fallback)"
fi

echo
echo "capture-screenshots: wrote $(ls -1 "$OUT_DIR"/*.png | wc -l) images to ${OUT_DIR#$REPO_ROOT/}"
echo "capture-screenshots: commit them — README.md already links these filenames."
echo "capture-screenshots: if blur/rounded corners are missing, this is a vanilla-sway system;"
echo "capture-screenshots: run scripts/install-swayfx.sh first and re-capture."
