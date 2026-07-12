#!/usr/bin/env bash
set -euo pipefail

PROFILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_FILE="$PROFILE_DIR/packages.x86_64"
VM_FILE="$PROFILE_DIR/vm-test.x86_64"
BACKUP_FILE="$PKG_FILE.bak"

cleanup() {
    if [ -f "$BACKUP_FILE" ]; then
        mv "$BACKUP_FILE" "$PKG_FILE"
        echo "Restored the real packages.x86_64 — committed file was never touched."
    fi
}
trap cleanup EXIT

cp "$PKG_FILE" "$BACKUP_FILE"
cat "$VM_FILE" >> "$PKG_FILE"

echo "Building test ISO with VM guest tools included..."
sudo mkarchiso -v -w /tmp/archiso-work -o "$PROFILE_DIR/out" "$PROFILE_DIR"