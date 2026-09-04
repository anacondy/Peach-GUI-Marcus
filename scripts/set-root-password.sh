#!/usr/bin/env bash
# scripts/set-root-password.sh
#
# Generates a shadow hash for the live image's root account and stages it where
# customize_airootfs.sh will pick it up at build time.
#
# The password is read from the terminal (never from argv, where it would land
# in `ps` and the shell history) and only the SHA-512 crypt hash is written to
# disk. That file is git-ignored, so no credential ever reaches the repository.
#
# Usage:  ./scripts/set-root-password.sh
#         ./scripts/set-root-password.sh --clear
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
OUT="${REPO_ROOT}/airootfs/etc/marcus/root-password-hash"

if [[ "${1:-}" == "--clear" ]]; then
    rm -f "$OUT"
    rmdir "$(dirname "$OUT")" 2>/dev/null || true
    echo "set-root-password: cleared — the image will boot with no root password (archiso default)"
    exit 0
fi

# Prefer openssl (present on essentially every build host). `mkpasswd` from
# whois is the fallback for hosts that lack it.
if command -v openssl >/dev/null 2>&1; then
    hash_cmd=(openssl passwd -6)
elif command -v mkpasswd >/dev/null 2>&1; then
    hash_cmd=(mkpasswd -m sha-512)
else
    echo "set-root-password: need either openssl or mkpasswd (whois package)" >&2
    exit 1
fi

echo "Enter the password to bake into the ISO as root's password."
echo "It is hashed locally; the plaintext is never written down or shown again."
read -r -s -p "Password: " pass1; echo
read -r -s -p "Confirm:  " pass2; echo

if [[ "$pass1" != "$pass2" ]]; then
    echo "set-root-password: passwords do not match — nothing written" >&2
    exit 1
fi
if [[ ${#pass1} -lt 8 ]]; then
    echo "set-root-password: refusing a password shorter than 8 characters" >&2
    exit 1
fi

hash="$("${hash_cmd[@]}" <<<"$pass1")"
# Drop our copies as soon as the hash exists.
pass1=""; pass2=""

mkdir -p "$(dirname "$OUT")"
printf '%s\n' "$hash" > "$OUT"
chmod 600 "$OUT"

echo "set-root-password: wrote ${OUT#$REPO_ROOT/} (mode 600, git-ignored)"
echo "set-root-password: the hash is consumed and deleted by customize_airootfs.sh during the build,"
echo "set-root-password: so it will not be present in the finished ISO."
