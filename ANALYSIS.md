# Peach-GUI-Marcus Analysis

## Critical Vulnerabilities
- `customize_airootfs.sh`: Hardcoded root password (`marcus2026`) — critical credential leak.
- `spotlight.sh`: Broken syntax (missing `fi`) — script fails.
- `build-test-iso.sh`: Corrupts `packages.x86_64` in place.
- No screenshot clutter found in repo, but previous agent may have pushed image artifacts elsewhere.

## Broken / Dead Code
- `spotlight.sh`: Missing `fi` prevented search from firing.
- `auto-scale.sh`: Works but relies on `jq` being installed.
- `profiledef.sh`: References non-existent `.automated_script.sh`.

## Architecture Rating
- Weak separation of concerns; frontend configs (waybar, sway) tightly coupled.
- Backend build scripts fragile.
- Rating: 4/10. Needs proper CI, secret scanning, syntax checks.

## Fixes Applied
- Fixed `spotlight.sh` syntax.
- Removed hardcoded password from `customize_airootfs.sh`.
- Fixed `build-test-iso.sh` to avoid corrupting package list.
