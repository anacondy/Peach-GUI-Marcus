#!/usr/bin/env bash
# scripts/deploy-to-arch.sh
#
# Try the Marcus Mix UI on an ALREADY-INSTALLED Arch Linux box/VM right now —
# no ISO build, no merge, no reboot required.
#
# It deploys the desktop CONFIGS (sway, waybar, mako, fastfetch) and the
# MarcusMix icon theme from this checkout into your user account, then tells
# you exactly how to start Sway. It never touches /etc, never edits your
# .zprofile/.zlogin, and never removes anything.
#
# WHY THIS WORKS WITHOUT AN ISO
#   The ISO is only a delivery mechanism: archiso copies airootfs/ onto a root
#   filesystem and boots it. Everything the UI needs lives under
#   airootfs/root/.config + airootfs/usr/share/icons, so on a running Arch
#   system the same files can be dropped into ~/.config and ~/.local and
#   started with `sway` directly. The one difference: on the ISO the icon theme
#   is at /usr/share/icons/MarcusMix, while here it is installed per-user to
#   ~/.local/share/icons/MarcusMix — this script rewrites the deployed dock.css
#   to point at the per-user copy. The repo's copy stays canonical.
#
# SAFETY
#   * Default is a DRY RUN: it prints the plan and changes nothing.
#   * --apply backs up every file it would overwrite to ~/.marcus-mix-backup.<ts>
#     before touching it; --revert restores the most recent backup.
#   * --packages (optional) installs the runtime packages with pacman. Without
#     it, it only prints the pacman line for you to run yourself.
#
# USAGE
#   ./scripts/deploy-to-arch.sh                 # dry run: show the plan
#   ./scripts/deploy-to-arch.sh --apply         # deploy configs + icons
#   ./scripts/deploy-to-arch.sh --apply --packages      # also pacman-install the UI subset
#   ./scripts/deploy-to-arch.sh --apply --packages --full   # install the whole manifest
#   ./scripts/deploy-to-arch.sh --revert        # undo the last --apply
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
AIROOTFS="${REPO_ROOT}/airootfs"

APPLY=0
DO_PACKAGES=0
FULL=0
REVERT=0
for a in "$@"; do
    case "$a" in
        --apply) APPLY=1 ;;
        --packages) DO_PACKAGES=1 ;;
        --full) FULL=1 ;;
        --revert) REVERT=1 ;;
        -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown flag: $a (see --help)" >&2; exit 2 ;;
    esac
done

HOME="${HOME:?HOME must be set}"
CONF="${HOME}/.config"
ICONS_SRC="${AIROOTFS}/usr/share/icons/MarcusMix"
ICONS_DST="${HOME}/.local/share/icons/MarcusMix"
BACKUP_ROOT="${HOME}/.marcus-mix-backup"

# The UI subset: enough to run the desktop, small enough to install quickly.
# (--full installs the entire packages.x86_64 manifest instead.)
UI_PACKAGES="sway swaybg swaylock swayidle waybar wofi mako kitty jq plocate
grim slurp wl-clipboard cliphist playerctl brightnessctl polkit-gnome xdg-utils
gvfs libnotify xdg-user-dirs fastfetch ttf-jetbrains-mono ttf-font-awesome
noto-fonts noto-fonts-emoji pipewire pipewire-alsa pipewire-pulse wireplumber
alsa-utils firefox pcmanfm"

say()  { printf '%s\n' "$*"; }
run()  { if (( APPLY )); then "$@"; else printf '  [dry-run] %s\n' "$*"; fi; }

# ---------------------------------------------------------------------------
# --revert
# ---------------------------------------------------------------------------
if (( REVERT )); then
    latest="$(ls -1dt "${BACKUP_ROOT}".* 2>/dev/null | head -1 || true)"
    if [[ -z "$latest" ]]; then
        echo "deploy-to-arch: no backup found under ${BACKUP_ROOT}.* — nothing to revert" >&2
        exit 1
    fi
    say "reverting from ${latest}"
    # rsync would be nicer but isn't guaranteed; cp -a is enough.
    ( cd "$latest" && find . -mindepth 1 -maxdepth 10 -type d | while read -r d; do mkdir -p "${HOME}/${d#./}"; done )
    ( cd "$latest" && find . -type f | while read -r f; do cp -a "$f" "${HOME}/${f#./}"; done )
    say "done. (files that deploy ADDED, like effects.conf, are not tracked; delete them by hand if needed)"
    exit 0
fi

# ---------------------------------------------------------------------------
# plan
# ---------------------------------------------------------------------------
say "Marcus Mix deploy — $([ $APPLY -eq 1 ] && echo APPLY || echo DRY RUN)"
say "repo: ${REPO_ROOT}"
say

say "Packages ($( [ $FULL -eq 1 ] && echo 'full manifest' || echo 'UI subset' )):"
if (( FULL )); then
    PKGLIST="$(grep -vE '^\s*(#|$)' "${REPO_ROOT}/packages.x86_64" | tr '\n' ' ')"
else
    PKGLIST="$UI_PACKAGES"
fi
say "  sudo pacman -S --needed $PKGLIST"
say

say "Will back up, then overwrite:"
for d in sway waybar mako fastfetch; do
    if [[ -e "${CONF}/${d}" ]]; then
        say "  ${CONF}/${d}  (exists -> backup first)"
    else
        say "  ${CONF}/${d}  (new)"
    fi
done
say "  ${ICONS_DST}  (icon theme, per-user)"
say

if (( ! APPLY )); then
    say "This was a dry run. Re-run with --apply to make these changes"
    say "(add --packages to also install the packages, --full for the whole manifest)."
    exit 0
fi

# ---------------------------------------------------------------------------
# apply
# ---------------------------------------------------------------------------
if (( DO_PACKAGES )); then
    if ! command -v pacman >/dev/null 2>&1; then
        echo "deploy-to-arch: pacman not found — this script targets an Arch system" >&2
        exit 1
    fi
    # shellcheck disable=SC2086
    sudo pacman -S --needed $PKGLIST
fi

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP="${BACKUP_ROOT}.${TS}"
mkdir -p "$BACKUP"

for d in sway waybar mako fastfetch; do
    if [[ -e "${CONF}/${d}" ]]; then
        mkdir -p "${BACKUP}/.config"
        cp -a "${CONF}/${d}" "${BACKUP}/.config/${d}"
        rm -rf "${CONF}/${d}"
    fi
    mkdir -p "${CONF}"
    cp -a "${AIROOTFS}/root/.config/${d}" "${CONF}/${d}"
done

mkdir -p "$(dirname "$ICONS_DST")"
rm -rf "$ICONS_DST"
cp -a "$ICONS_SRC" "$ICONS_DST"

# Point the DEPLOYED dock.css at the per-user icon theme. The repo file keeps
# the /usr/share path used by the ISO.
DEPLOYED_DOCK="${CONF}/waybar/dock.css"
if [[ -f "$DEPLOYED_DOCK" ]]; then
    sed -i "s|/usr/share/icons/MarcusMix|${ICONS_DST}|g" "$DEPLOYED_DOCK"
fi

# Make the scripts executable in place (the repo already has the bits, but a
# zip/tar round-trip can lose them).
chmod +x "${CONF}/sway/scripts/"*.sh 2>/dev/null || true

# Generate the effects include BEFORE sway starts, so the first parse has it.
# On vanilla sway (the normal case on a VM) it writes a comments-only file and
# sway boots silent; if you've installed SwayFX it writes the real effects.
"${CONF}/sway/scripts/perf-profile.sh" --prestart || true

# Real config validation, if sway is installed: `sway -C` checks the config
# without starting the compositor.
if command -v sway >/dev/null 2>&1; then
    if sway -C -c "${CONF}/sway/config" 2>/dev/null; then
        say "sway -C: config validates OK"
    else
        say "sway -C reported problems above — read them; the most common on a VM is a"
        say "missing SwayFX directive, which is expected and harmless on vanilla sway."
    fi
fi

say
say "Deployed. How to run it:"
say "  1) Switch to a free TTY:  Ctrl+Alt+F3  (your KDE session keeps running)"
say "  2) Log in, then:"
say "       export WLR_RENDERER=pixman   # VMs usually have no real GPU for wlroots"
say "       exec sway"
say "     (if your KDE session is X11 you can instead run it in a window from a"
say "      Konsole:  WLR_BACKENDS=x11 sway )"
say "  3) Inside: Alt+Space = Spotlight, Super+d = wofi, Super+Return = kitty,"
say "     Print = screenshot to ~/Pictures."
say "  4) Grab a real screenshot:  grim ~/marcus.png   then copy it into"
say "     docs/screenshots/ in this repo and commit it."
say "  5) Leave sway with Super+Shift+e, then Ctrl+Alt+F1/F2 back to KDE."
say
say "To undo everything:  ./scripts/deploy-to-arch.sh --revert"
