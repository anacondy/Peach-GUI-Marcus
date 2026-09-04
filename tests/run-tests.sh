#!/usr/bin/env bash
# tests/run-tests.sh
#
# Runs the whole suite. No test framework, no Python dependencies beyond the
# standard library, nothing to install.
#
#   ./tests/run-tests.sh              everything
#   ./tests/run-tests.sh configs      one module by name
#
# What this suite can and cannot prove:
#
#   CAN  - every script parses; every config parses; every module, token, font,
#          icon, package and file path referenced by the configs actually exists;
#          the build script stages a valid profile without touching the work
#          tree; perf-profile.sh computes the right render latency and quality
#          tier for each refresh rate; spotlight.sh assembles, caches and
#          dispatches correctly; no credential is committed.
#
#   CANNOT - that the ISO boots, that sway renders a frame, that waybar draws a
#          glyph, that blur costs what the tier table assumes, or that anything
#          holds 60 FPS. Those need a compositor, a display and a GPU. There is
#          no substitute for flashing the image and running it; see
#          scripts/capture-screenshots.sh and docs/AUDIT-*.md.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$TESTS_DIR/.."

MODULES=(test_configs.py test_wiring.py test_perf_profile.py
         test_build_script.py test_spotlight.py test_pqc_audit.py)

if [[ $# -gt 0 ]]; then
    MODULES=()
    for want in "$@"; do
        MODULES+=("test_${want}.py")
    done
fi

overall=0
for mod in "${MODULES[@]}"; do
    if [[ ! -f "tests/$mod" ]]; then
        echo "no such test module: tests/$mod" >&2
        overall=1
        continue
    fi
    echo
    echo "== $mod =="
    python3 "tests/$mod" || overall=1
done

echo
echo "=========================================================="
if (( overall == 0 )); then
    echo " ALL SUITES PASSED"
else
    echo " FAILURES ABOVE"
fi
echo "=========================================================="
exit "$overall"
