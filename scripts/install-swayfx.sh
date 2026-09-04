#!/usr/bin/env bash
# scripts/install-swayfx.sh
#
# Post-install helper: builds and installs SwayFX on a machine already running
# Marcus Mix.
#
# WHY THIS ISN'T IN packages.x86_64
#   SwayFX is not in Arch's official repositories — it is AUR-only. archiso
#   installs a profile's packages with pacman against the official mirrors
#   inside a chroot, with no AUR helper and no build user, so an AUR package
#   simply cannot be baked into the ISO this way. Everything the config asks for
#   that is SwayFX-only (corner_radius, blur, shadows, layer_effects,
#   default_dim_inactive) is therefore inert on the ISO as built, and
#   perf-profile.sh generates a comments-only effects.conf so that vanilla sway
#   doesn't log an error for each of those lines.
#
# WHAT IT COSTS YOU IF YOU SKIP IT
#   No rounded corners, no blur, no drop shadows, no inactive-window dimming.
#   The dock, the top bar, the keybindings, the launcher, the taskbar, the
#   scaling and the render-latency tuning all work regardless — the compositor is
#   still sway, SwayFX is a fork that adds the effects backend.
#
# Run this on the TARGET machine after installing, as a non-root user with sudo:
#     ./scripts/install-swayfx.sh
set -euo pipefail

if ! command -v pacman >/dev/null 2>&1; then
    echo "install-swayfx: pacman not found — this script is for an installed Arch system, not a live ISO." >&2
    exit 1
fi

if ! pacman -Qi swayfx >/dev/null 2>&1; then
    echo "install-swayfx: building swayfx from the AUR (needs base-devel, which is already in packages.x86_64)"
    if ! command -v makepkg >/dev/null 2>&1; then
        echo "install-swayfx: makepkg missing — sudo pacman -S --needed base-devel" >&2
        exit 1
    fi

    WORK="$(mktemp -d -t swayfx.XXXXXX)"
    trap 'rm -rf "$WORK"' EXIT

    # Fetch the PKGBUILD rather than cloning a repo: it is one file, and it is
    # the file makepkg is going to act on, so there is nothing else to trust.
    echo "install-swayfx: fetching PKGBUILD from https://aur.archlinux.org/swayfx.git"
    curl -fL --retry 3 -o "$WORK/PKGBUILD" \
        "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=swayfx"

    echo
    echo "install-swayfx: READ THIS PKGBUILD BEFORE CONTINUING."
    echo "install-swayfx: it is community-maintained and will run as your user."
    echo
    read -r -p "install-swayfx: continue? [y/N] " answer
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]] || { echo "install-swayfx: aborted"; exit 1; }

    cd "$WORK"
    # makepkg refuses to run as root; drop to the invoking user if we were sudo'd.
    if [[ "$(id -u)" -eq 0 ]]; then
        BUILD_USER="${SUDO_USER:-}"
        [[ -n "$BUILD_USER" ]] || { echo "install-swayfx: ran as root without SUDO_USER; re-run as a normal user" >&2; exit 1; }
        chown "$BUILD_USER" "$WORK"
        sudo -u "$BUILD_USER" makepkg -sf --noconfirm
    else
        makepkg -sf --noconfirm
    fi

    sudo pacman -U --noconfirm ./*.pkg.tar.*
fi

# SwayFX replaces sway's binary; the config file needs no edits. Removing the
# vanilla sway package is what makes the effects directives live.
if pacman -Qi sway >/dev/null 2>&1 && pacman -Qi swayfx >/dev/null 2>&1; then
    echo "install-swayfx: both sway and swayfx are installed; removing vanilla sway"
    sudo pacman -Rdd --noconfirm sway
fi

# Clear the memo perf-profile.sh keeps so it re-detects SwayFX and rewrites
# effects.conf with the real effect directives instead of the comments-only file.
rm -f "$HOME/.cache/marcus-mix/perf-state"

echo
echo "install-swayfx: done. Reload with 'swaymsg reload' (or log out and back in)."
echo "install-swayfx: check what tier it picked:"
echo "    cat ~/.config/sway/effects.conf"
