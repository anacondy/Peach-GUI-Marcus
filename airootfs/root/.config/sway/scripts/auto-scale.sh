#!/usr/bin/env bash
# ~/.config/sway/scripts/auto-scale.sh
#
# Sets a sensible `output <name> scale <factor>` for every connected display,
# so fonts/icons stay a comfortable physical size whether you're on the
# laptop panel, a 1080p external, or a 4K one — instead of one fixed scale
# that's right for exactly one screen and wrong everywhere else.
#
# Strategy: compute pixels-per-inch from the monitor's reported physical size
# when that data looks sane, otherwise fall back to a resolution-only tier.
# Physical-size EDID data is genuinely unreliable on a lot of cheap panels and
# cables, so the fallback isn't a rare edge case, it's the common case on
# budget hardware — this script is written assuming it'll be hit often.
#
# Run at sway startup (see config/sway-theme.conf). Re-run manually after
# plugging in a new monitor:
#   ~/.config/sway/scripts/auto-scale.sh
#
# Requires: jq

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
    notify-send "Marcus Mix" "auto-scale.sh needs 'jq' — add it to packages.x86_64" 2>/dev/null || true
    exit 1
fi

# width_px height_px -> scale, for when we can't trust physical size.
# 4K (h<=2300) defaults to 1.5 rather than higher: a 4K *external monitor*
# (27-32", ~140-165ppi, conventionally 150%) is far more common in the wild
# than a small high-density 4K *laptop* panel (~280-340ppi, conventionally
# 200%) — and this branch only runs when we have no size data to tell them
# apart, so it's biased toward the more likely case.
scale_from_resolution() {
    local h="$1"
    if   (( h <= 800  )); then echo "1"
    elif (( h <= 1200 )); then echo "1"
    elif (( h <= 1500 )); then echo "1.25"
    elif (( h <= 1900 )); then echo "1.5"
    elif (( h <= 2300 )); then echo "1.5"
    else echo "2"
    fi
}

# ppi -> scale, calibrated against real-world conventions rather than a
# straight ppi/96 division (which overshoots badly — e.g. it would put a
# 27in 4K monitor at 170% against the well-established convention of 150%,
# and a 13in 4K laptop panel at 345% against the convention of 200%).
scale_from_ppi() {
    local ppi="$1"
    if   awk -v p="$ppi" 'BEGIN{exit !(p<110)}'; then echo "1"
    elif awk -v p="$ppi" 'BEGIN{exit !(p<135)}'; then echo "1.25"
    elif awk -v p="$ppi" 'BEGIN{exit !(p<170)}'; then echo "1.5"
    elif awk -v p="$ppi" 'BEGIN{exit !(p<200)}'; then echo "1.75"
    else echo "2"
    fi
}

# Round to the nearest 0.05 so sway gets a clean fractional-scale value
round_scale() {
    awk -v s="$1" 'BEGIN{printf "%.2f", int(s/0.05+0.5)*0.05}'
}

swaymsg -t get_outputs -r | jq -c '.[]' | while read -r out; do
    name=$(jq -r '.name' <<<"$out")
    active=$(jq -r '.active' <<<"$out")
    [[ "$active" == "true" ]] || continue

    width=$(jq -r '.current_mode.width  // 0' <<<"$out")
    height=$(jq -r '.current_mode.height // 0' <<<"$out")
    (( width > 0 && height > 0 )) || continue

    # Different sway/wlroots versions have exposed physical size under
    # different keys over time — try the plausible ones, treat 0/missing as
    # "not trustworthy" rather than guessing with bad data.
    phys_w=$(jq -r '(.phys_width // .physical_size.width // 0)' <<<"$out")
    phys_h=$(jq -r '(.phys_height // .physical_size.height // 0)' <<<"$out")

    scale="0"
    if (( phys_w > 30 && phys_h > 30 )); then
        # ppi from the diagonal, so aspect-ratio quirks don't skew it
        ppi=$(awk -v w="$width" -v h="$height" -v pw="$phys_w" -v ph="$phys_h" \
            'BEGIN{ diag_px=sqrt(w*w+h*h); diag_in=sqrt(pw*pw+ph*ph)/25.4; if (diag_in>0) printf "%.1f", diag_px/diag_in; else print 0 }')
        # Sanity bounds: real panels land roughly 80-360ppi (the high end
        # covers small high-density laptop panels, e.g. 13in 4K ~330ppi).
        # Outside that, the EDID data is almost certainly wrong -> fall back.
        if awk -v p="$ppi" 'BEGIN{exit !(p>=80 && p<=360)}'; then
            scale=$(scale_from_ppi "$ppi")
        fi
    fi

    if [[ "$scale" == "0" ]]; then
        scale=$(scale_from_resolution "$height")
    fi
    scale=$(round_scale "$scale")

    swaymsg output "$name" scale "$scale" >/dev/null
    echo "auto-scale: $name (${width}x${height}) -> scale $scale"
done
