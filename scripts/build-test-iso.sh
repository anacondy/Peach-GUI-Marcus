#!/usr/bin/env bash
# scripts/build-test-iso.sh
#
# Builds a VM-friendly TEST ISO from this repository's archiso profile, with the
# VirtualBox/QEMU guest agents from scripts/vm-test.x86_64 merged in.
#
# ---------------------------------------------------------------------------
# THE BUG THIS FILE USED TO HAVE
# ---------------------------------------------------------------------------
# Commit a1925bc ("refactor: move helper scripts to dedicated scripts directory")
# moved this file into scripts/ but left its path resolution alone:
#
#     PROFILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#     PKG_FILE="$PROFILE_DIR/packages.x86_64"
#
# dirname of scripts/build-test-iso.sh is scripts/, so it looked for
# scripts/packages.x86_64 - which has never existed. Both branches shipped it
# broken. Verified failure, reproduced here:
#
#     $ bash scripts/build-test-iso.sh
#     cp: cannot stat '.../scripts/packages.x86_64': No such file or directory
#
# The profile (profiledef.sh, pacman.conf, packages.x86_64, airootfs/) lives at
# the REPOSITORY ROOT, not next to this script. REPO_ROOT below is the fix.
#
# ---------------------------------------------------------------------------
# WHY WE COPY INSTEAD OF APPEND-AND-RESTORE
# ---------------------------------------------------------------------------
# The old script appended vm-test.x86_64 onto the committed packages.x86_64 and
# restored it from a .bak on EXIT. Two problems: it mutated a tracked file in
# your work tree while you were working, and a SIGKILL/OOM left the tracked file
# permanently polluted with virtualbox-guest-utils-nox. We now stage a throwaway
# copy of the profile in a temp dir and never touch the work tree at all.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

PKG_FILE="${REPO_ROOT}/packages.x86_64"
VM_FILE="${SCRIPT_DIR}/vm-test.x86_64"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/out}"

for f in "$PKG_FILE" "$VM_FILE" "${REPO_ROOT}/profiledef.sh" "${REPO_ROOT}/pacman.conf"; do
    [[ -f "$f" ]] || { echo "build-test-iso: missing $f" >&2; exit 1; }
done
[[ -d "${REPO_ROOT}/airootfs" ]] || { echo "build-test-iso: missing airootfs/" >&2; exit 1; }

if ! command -v mkarchiso >/dev/null 2>&1; then
    echo "build-test-iso: mkarchiso not found. Install archiso on the build host:" >&2
    echo "    sudo pacman -S --needed archiso" >&2
    exit 1
fi

STAGE="$(mktemp -d -t marcus-profile.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT INT TERM

PROFILE="${STAGE}/profile"
mkdir -p "$PROFILE"

# Copy the profile, excluding the VCS dir and any previous build output. tar is
# used rather than cp -a so that the exclude list works the same on every coreutils
# version; the repo is a few dozen kilobytes of configs, so this is instant.
tar -C "$REPO_ROOT" \
    --exclude=./.git --exclude=./out --exclude=./work --exclude=./.arena \
    -cf - . | tar -C "$PROFILE" -xf -

# Merge the VM guest tools into the STAGED package list only.
cat "$PKG_FILE" "$VM_FILE" > "${PROFILE}/packages.x86_64"

MERGED="$(grep -cvE '^\s*(#|$)' "${PROFILE}/packages.x86_64" || true)"
echo "build-test-iso: profile staged at $PROFILE"
echo "build-test-iso: $MERGED packages (base list + VM guest agents)"
echo "build-test-iso: output -> $OUT_DIR"
echo

mkdir -p "$OUT_DIR"

# mkarchiso must run as root. Use sudo only if we are not already root.
SUDO=""
[[ "$(id -u)" -eq 0 ]] || SUDO="sudo"

# shellcheck disable=SC2086
$SUDO mkarchiso -v -w "${STAGE}/work" -o "$OUT_DIR" "$PROFILE"

echo
echo "build-test-iso: done. ISO in $OUT_DIR"
echo "build-test-iso: the work tree was never modified - \`git status\` stays clean."
