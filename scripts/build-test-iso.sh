#!/usr/bin/env bash
set -euo pipefail

PROFILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_FILE="$PROFILE_DIR/packages.x86_64"
VM_FILE="$PROFILE_DIR/vm-test.x86_64"
BACKUP_FILE="$PKG_FILE.bak"

cleanup() {
    rm -f "$BACKUP_FILE" "${PKG_FILE}.tmp"
    echo "Cleaned up temporary build artifacts."
}
trap cleanup EXIT

cp -f "$PKG_FILE" "$BACKUP_FILE"
cp -f "$PKG_FILE" "${PKG_FILE}.tmp"
cat "$VM_FILE" >> "${PKG_FILE}.tmp"

# Use temporary package file for build to avoid corrupting committed file
PROFILE_PKG="${PKG_FILE}.tmp"

echo "Building test ISO with VM guest tools included..."
sudo mkarchiso -v -w /tmp/archiso-work -o "$PROFILE_DIR/out" -p "$PROFILE_PKG" "$PROFILE_DIR" || true
# Restore committed file immediately
mv -f "$BACKUP_FILE" "$PKG_FILE"
rm -f "${PKG_FILE}.tmp"