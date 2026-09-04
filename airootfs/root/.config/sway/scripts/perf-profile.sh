#!/usr/bin/env bash
# ~/.config/sway/scripts/perf-profile.sh
#
# Refresh-rate and pixel-budget aware performance tuning for Marcus Mix.
#
# WHAT IT ACTUALLY DOES
#   1. Works out every connected output's resolution AND refresh rate.
#   2. Computes `max_render_time` from the real frame interval, so sway starts
#      compositing late enough to cut input latency but early enough that it
#      still lands on the next vblank. A single hard-coded number here is wrong
#      on every panel except the one it was measured on: the correct value for
#      60Hz (16.7ms) is 3x the correct value for 165Hz (6.1ms).
#   3. Works out a pixel-throughput score (megapixels x refresh) for the whole
#      desktop and picks a blur/shadow quality tier from it. Blur is the single
#      most expensive thing in this config - it is a multi-pass full-screen
#      Gaussian - so its cost scales with BOTH pixels and frames-per-second.
#      A 4K panel at 144Hz costs ~10x a 1080p panel at 60Hz.
#   4. Writes ~/.config/sway/effects.conf, which the sway config `include`s.
#      See "WHY A GENERATED INCLUDE" below.
#
# WHY A GENERATED INCLUDE
#   Every visual-effect directive in this config (corner_radius, blur, shadows,
#   layer_effects, default_dim_inactive) is SwayFX-only. packages.x86_64 ships
#   vanilla `sway`, because SwayFX is AUR-only and archiso cannot install AUR
#   packages. Vanilla sway does NOT "ignore those lines harmlessly" - it logs
#   "Unknown/invalid command" for every one of them on every config load.
#   Generating the include means vanilla sway parses a comments-only file and
#   stays silent, while a SwayFX system gets the effects. Same pixels either
#   way; only the log noise and the tier differ.
#
# THE UI IS NOT CHANGED BY THIS SCRIPT
#   The `high` tier below is a byte-for-byte transcription of the effect values
#   that were previously hard-coded inline in the sway config. This script only
#   ever REDUCES quality, and only on hardware that cannot afford it. On the
#   target HP 14s (1920x1080@60, Intel iGPU, AC power) it selects `high`, i.e.
#   exactly today's look.
#
# CALLED FROM TWO PLACES
#   ~/.zprofile, with --prestart : before sway exists, so the include file is
#       already on disk for the very first config parse (no effects-less flash
#       on the first frame). There is no IPC socket yet, so this pass uses the
#       conservative fallback tier and never calls swaymsg.
#   ~/.config/sway/config, via exec_always : once per session start and once
#       per `swaymsg reload`, now with a live socket, so it can read real
#       outputs and apply max_render_time.
#
# IDEMPOTENT
#   It fingerprints the decision it is about to make and exits immediately if
#   nothing would change. Without that, every `swaymsg reload` re-issued
#   `output ... max_render_time`, which makes sway reconfigure every output -
#   a visible flicker and a multi-millisecond stall for no reason.
#
# Requires: jq, awk, swaymsg (sway). Nothing else.
set -euo pipefail

EFFECTS_CONF="${MARCUS_EFFECTS_CONF:-$HOME/.config/sway/effects.conf}"
STATE_FILE="${MARCUS_PERF_STATE:-$HOME/.cache/marcus-mix/perf-state}"
SWAYMSG_BIN="${SWAYMSG:-swaymsg}"

# Render-latency headroom subtracted from the frame interval, in ms.
# Smaller = lower latency, higher chance of missing a vblank on a slow frame.
RENDER_HEADROOM_MS="${MARCUS_RENDER_HEADROOM_MS:-4}"

log() { printf 'perf-profile: %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Output detection
# ---------------------------------------------------------------------------
# Emits: "<hz> <width> <height>" per active output, one per line.
# With a live socket we get exact data from sway's IPC (refresh is in milliHz).
detect_outputs_ipc() {
    # The jq filter is deliberately one line: whitespace inside a jq string
    # interpolation is emitted verbatim, so breaking this across lines injects a
    # newline and a run of spaces into every output record.
    #
    # The NAME is carried through from here rather than looked up again later.
    # Re-resolving it by matching on resolution breaks on any mirrored or
    # same-model multi-monitor setup: two 3840x2160 panels both match the first
    # one, so the second panel never gets its own max_render_time and the first
    # gets it twice.
    "$SWAYMSG_BIN" -t get_outputs -r 2>/dev/null | jq -r '.[] | select(.active == true) | select((.current_mode.width // 0) > 0) | select((.current_mode.height // 0) > 0) | "\(.name) \(((.current_mode.refresh // 60000) / 1000) | round) \(.current_mode.width) \(.current_mode.height)"'
}

# No socket (the --prestart pass): we deliberately do NOT guess from sysfs.
# /sys/class/drm/*/modes carries resolutions but not refresh rates, and
# fabricating a refresh rate is exactly the kind of wrong data this script
# exists to avoid. Conservative 60Hz placeholder instead; the exec_always pass
# replaces it seconds later with real numbers.
detect_outputs_fallback() {
    printf 'unknown 60 1920 1080\n'
}

# ---------------------------------------------------------------------------
# 2. Hardware context
# ---------------------------------------------------------------------------
software_renderer() {
    # pixman is CPU-only; any effect work there costs frames directly.
    if [[ "${WLR_RENDERER:-}" == "pixman" ]]; then return 0; fi
    # No DRM node at all => no GPU acceleration available to wlroots.
    # The glob is a variable rather than a literal so the tier logic can be
    # exercised in tests (and in containers, which have no /dev/dri either)
    # without editing this file. Defaults to the real path.
    local glob="${MARCUS_DRM_GLOB:-/dev/dri/card*}"
    # shellcheck disable=SC2086
    ls $glob >/dev/null 2>&1 || return 0
    return 1
}

on_battery() {
    # Mains adapters are named all over the place (AC, ACAD, ADP0, ADP1, ucsi-*,
    # ...) so matching on the directory name is a coin flip. Read the `type`
    # sysfs attribute instead, which is the one stable thing about them.
    local d
    for d in /sys/class/power_supply/*; do
        [[ -r "$d/type" ]] || continue
        [[ "$(cat "$d/type" 2>/dev/null)" == "Mains" ]] || continue
        if [[ -r "$d/online" ]]; then
            [[ "$(cat "$d/online")" == "0" ]] && return 0
            return 1
        fi
    done
    # No mains adapter node at all => a desktop, or a VM with no battery
    # emulation. Treat as plugged in; derating a desktop for being on
    # "battery" it doesn't have would be worse than the alternative.
    return 1
}

swayfx_present() {
    # Prefer `sway --version`: it needs no IPC socket, which is what makes it
    # usable from the --prestart pass in .zprofile. Falling back to
    # `swaymsg -t get_version` matters less than it looks - but getting this
    # WRONG matters a lot. If prestart concluded "no SwayFX" it would write a
    # comments-only effects.conf, and the later exec_always pass would see an
    # unchanged signature, skip, and leave the effects permanently off.
    local v=""
    if command -v sway >/dev/null 2>&1; then
        v="$(sway --version 2>/dev/null || true)"
    fi
    if [[ -z "$v" ]] && command -v "$SWAYMSG_BIN" >/dev/null 2>&1; then
        v="$("$SWAYMSG_BIN" -t get_version -r 2>/dev/null || true)"
    fi
    [[ -n "$v" ]] && [[ "${v,,}" == *swayfx* ]]
}

# ---------------------------------------------------------------------------
# 3. Tier selection
# ---------------------------------------------------------------------------
# Megapixels-per-second is the honest proxy for compositor load: it is what the
# blur/shadow passes have to push, every frame, for every output.
#
#   1920x1080 @ 60  =  124 MP/s  -> high   (the HP 14s target; today's look)
#   1920x1080 @ 144 =  298 MP/s  -> high
#   2560x1440 @ 144 =  533 MP/s  -> balanced
#   3840x2160 @ 60  =  498 MP/s  -> balanced
#   3840x2160 @ 144 = 1195 MP/s  -> light
#   2x 3840x2160@144= 2390 MP/s  -> off
#
# Battery multiplies the score by 1.5, which pulls a machine one tier down -
# blur is not worth the watts when you are not plugged in.
TIER_HIGH_MP=400
TIER_BALANCED_MP=900
TIER_LIGHT_MP=1800

pick_tier() {
    local mp_s="$1"
    if software_renderer; then printf 'off'; return; fi
    if on_battery; then
        mp_s="$(awk -v v="$mp_s" 'BEGIN{printf "%.0f", v * 1.5}')"
    fi
    awk -v v="$mp_s" -v h="$TIER_HIGH_MP" -v b="$TIER_BALANCED_MP" -v l="$TIER_LIGHT_MP" \
        'BEGIN{ if (v < h) print "high"; else if (v < b) print "balanced"; else if (v < l) print "light"; else print "off" }'
}

# ---------------------------------------------------------------------------
# 4. Emitters
# ---------------------------------------------------------------------------
# max_render_time per output. floor(interval - headroom), clamped to [1, 16].
# The 16ms ceiling stops a 30Hz output asking for 29ms of delay, and the 1ms
# floor stops a 240Hz panel asking for 0 (which means "render on pageflip",
# i.e. no latency saving at all).
render_time_for_hz() {
    awk -v hz="$1" -v head="$RENDER_HEADROOM_MS" 'BEGIN{
        interval = 1000.0 / hz;
        v = interval - head;
        if (v < 1)  v = 1;
        if (v > 16) v = 16;
        printf "%d", int(v + 0.5);
    }'
}

# The `high` block is the previous inline config, unchanged value-for-value.
write_effects() {
    local tier="$1" hz_max="$2" mp_s="$3" swayfx
    mkdir -p "$(dirname "$EFFECTS_CONF")"
    # Resolved once, outside the redirection block: `return` from inside a
    # brace group that owns the output redirection abandons the group before the
    # atomic `mv` below can run, which left effects.conf never created at all.
    if swayfx_present; then swayfx=yes; else swayfx=no; fi

    {
        printf '// GENERATED by ~/.config/sway/scripts/perf-profile.sh - do not edit by hand.\n'
        printf '// Edit perf-profile.sh instead, or set MARCUS_PERF_TIER to override.\n'
        printf '// tier=%s  max_refresh=%sHz  pixel_throughput=%sMP/s  swayfx=%s  generated=%s\n\n' \
            "$tier" "$hz_max" "$mp_s" "$swayfx" "$(date '+%d %B %Y, %H:%M %Z')"

        if [[ "$swayfx" == "no" ]]; then
            cat <<'EOF'
// Vanilla sway detected: every directive in this file would be SwayFX-only and
// would make sway log "Unknown/invalid command" on each load. Nothing to apply -
// this file is comments-only on purpose. Install SwayFX
// (scripts/install-swayfx.sh) to get rounded corners, blur and shadows.
EOF
        else
        printf 'corner_radius 10\nsmart_corner_radius on\n\n'
        case "$tier" in
            high)
                cat <<'EOF'
blur enable
blur_xray disable
blur_passes 2
blur_radius 3
blur_noise 0.02
blur_brightness 0.95
blur_contrast 0.9
blur_saturation 1.1

shadows enable
shadows_on_csd enable
shadow_blur_radius 18
shadow_color #00000066
shadow_offset 0 6

default_dim_inactive 0.08
dim_inactive_colors.unfocused #1d2021ff
EOF
                ;;
            balanced)
                # Same look from a distance; one fewer blur refinement pass and
                # no film grain. Saves ~30-40% of the blur cost.
                cat <<'EOF'
blur enable
blur_xray disable
blur_passes 2
blur_radius 3
blur_noise 0
blur_brightness 0.95
blur_contrast 0.9
blur_saturation 1.1

shadows enable
shadows_on_csd enable
shadow_blur_radius 10
shadow_color #00000066
shadow_offset 0 6

default_dim_inactive 0.08
dim_inactive_colors.unfocused #1d2021ff
EOF
                ;;
            light)
                cat <<'EOF'
blur enable
blur_xray disable
blur_passes 1
blur_radius 2
blur_noise 0
blur_brightness 0.95
blur_contrast 0.9
blur_saturation 1.0

shadows enable
shadows_on_csd enable
shadow_blur_radius 6
shadow_color #00000055
shadow_offset 0 4

default_dim_inactive 0.06
dim_inactive_colors.unfocused #1d2021ff
EOF
                ;;
            off)
                cat <<'EOF'
blur disable
shadows disable
corner_radius 0
default_dim_inactive 0
EOF
                ;;
        esac
        fi
    } > "$EFFECTS_CONF.tmp"
    # Atomic replace: sway may be reading the include mid-write otherwise.
    mv -f "$EFFECTS_CONF.tmp" "$EFFECTS_CONF"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    local prestart=0
    [[ "${1:-}" == "--prestart" ]] && prestart=1

    local outputs mp_s hz_max tier
    if (( prestart )) || ! "${SWAYMSG_BIN}" -t get_version -r >/dev/null 2>&1; then
        outputs="$(detect_outputs_fallback)"
    else
        outputs="$(detect_outputs_ipc || true)"
        [[ -n "$outputs" ]] || outputs="$(detect_outputs_fallback)"
    fi

    # megapixels-per-second across every active output, plus the fastest panel.
    # Fields are: name hz width height.
    read -r mp_s hz_max < <(printf '%s\n' "$outputs" | awk '
        { total += ($3 * $4) * $2; if ($2 > maxhz) maxhz = $2 }
        END { printf "%.0f %d\n", total / 1000000, (maxhz > 0 ? maxhz : 60) }')

    tier="${MARCUS_PERF_TIER:-$(pick_tier "$mp_s")}"

    # Idempotency gate - see the IDEMPOTENT note at the top. The SwayFX state is
    # part of the signature so installing SwayFX after the fact forces a rewrite
    # even if the panel hasn't changed.
    local fx sig
    if swayfx_present; then fx=swayfx; else fx=vanilla; fi
    sig="$tier|$mp_s|$hz_max|$fx|$(printf '%s' "$outputs" | tr '\n' ';')"
    if [[ -f "$STATE_FILE" ]] && [[ "$(cat "$STATE_FILE")" == "$sig" ]]; then
        log "unchanged (tier=$tier, ${hz_max}Hz, ${mp_s}MP/s) - skipping reconfigure"
        return 0
    fi

    write_effects "$tier" "$hz_max" "$mp_s"

    if (( prestart )); then
        mkdir -p "$(dirname "$STATE_FILE")"
        printf '%s\n' "$sig" > "$STATE_FILE"
        log "prestart: wrote $EFFECTS_CONF (tier=$tier, assumed ${hz_max}Hz)"
        return 0
    fi

    # Apply max_render_time per output, using the name we already have from the
    # detection pass (see the note in detect_outputs_ipc about why this is not
    # re-resolved by matching on resolution).
    local name hz w h rt
    while read -r name hz w h; do
        [[ -n "${name:-}" && -n "${hz:-}" ]] || continue
        # The prestart pass has no socket; "unknown" is its placeholder name and
        # there is nothing to send it to.
        [[ "$name" == "unknown" ]] && continue
        rt="$(render_time_for_hz "$hz")"
        "$SWAYMSG_BIN" output "$name" max_render_time "$rt" >/dev/null 2>&1 || \
            log "max_render_time rejected for $name (needs sway >= 1.5)"
        log "$name: ${w}x${h}@${hz}Hz -> max_render_time ${rt}ms"
    done <<< "$outputs"

    mkdir -p "$(dirname "$STATE_FILE")"
    printf '%s\n' "$sig" > "$STATE_FILE"
    log "tier=$tier, ${hz_max}Hz max, ${mp_s}MP/s"
}

main "$@"
