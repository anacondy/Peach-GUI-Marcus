#!/bin/sh
# ~/.config/sway/scripts/start-dock.sh
#
# Starts the Marcus Mix dock (a second waybar instance) and is safe to run more
# than once, which it must be: sway invokes it via `exec_always`, and
# `exec_always` re-runs on every `swaymsg reload` WITHOUT stopping the process it
# started last time. Launching waybar directly here stacked a new dock on top of
# the old one on every reload - after three reloads you had three overlapping
# docks eating three times the CPU for one bar's worth of pixels.
#
# We kill only the dock instance, never the main top bar. `pgrep -x waybar`
# matches processes whose executable name is exactly "waybar", so this cannot
# accidentally match this shell's own command line the way a `pkill -f dock.jsonc`
# pattern would.

for pid in $(pgrep -x waybar 2>/dev/null); do
    if tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q 'dock\.jsonc'; then
        kill "$pid" 2>/dev/null || true
    fi
done

exec waybar -c "$HOME/.config/waybar/dock.jsonc" -s "$HOME/.config/waybar/dock.css"
