# Analysis (corrected)

This supersedes the `ANALYSIS.md` that lived on the remote-only branch
`arena/019f7c2f-peach-gui-marcus`. That document was a useful starting point and
its three goals — remove the hardcoded secret, stop the build script from
mutating `packages.x86_64`, and add analysis — were right. Several of its
specific claims were wrong; the full, evidence-tagged record is in
[`docs/AUDIT-2026-09-04.md`](docs/AUDIT-2026-09-04.md) and the post-quantum plan
in [`docs/PQC-THREAT-MODEL.md`](docs/PQC-THREAT-MODEL.md). Corrections, briefly:

* **Build script.** It was broken on *both* branches: after the move into
  `scripts/` it resolved its profile as `dirname $0`, so `mkarchiso` got a
  directory with no `packages.x86_64`/`airootfs`. The other branch's "fix" also
  used a `mkarchiso -p <file>` flag that mkarchiso does not accept for a package
  list, and an `|| true` that hid failure. Fixed properly by staging a throwaway
  profile copy.
* **Root password.** Removed from `customize_airootfs.sh`. The string is not
  repeated anywhere in this repo; `tests/test_configs.py::test_no_secrets_in_the_repo`
  fails the build if it (or any inline credential) returns. Build-time hashes go
  through `scripts/set-root-password.sh`; otherwise the image boots with no root
  password, which is upstream archiso's live-image default.
* **`.zlogin` / `.zprofile`.** The other branch deleted these; they are the files
  that autostart Sway on tty1. Restored, plus a guard so `.zlogin` no longer runs
  the unshipped `~/.automated_script.sh`.
* **`spotlight.sh`.** Was already syntactically fine (`bash -n`); the real bugs
  were a world-readable home index (now 600) and a `%[a-zA-Z]` field-code strip
  that mangled real percent signs.
* **Waybar.** `RAM {}%` (not a token) → `{percentage}`; empty `format-icons` →
  real Font Awesome codepoints; clock pinned to `Asia/Kolkata` with a
  Day-Month-Year tooltip; `ttf-jetbrains-mono` and `libnotify` added to the
  manifest.

## Verification (what was actually run)

`tests/run-tests.sh` → **63 tests, 0 failures**, plus `bash -n` clean on every
shell file, `scripts/pqc-audit` run live, and `tools/render-preview.mjs`
producing the previews in `docs/previews/`. The build-script and secret tests
were pointed at the old code and failed it, so the suite is a real regression
net, not a self-congratulation.

## What this environment cannot prove

Booting the ISO, sway/waybar rendering, SwayFX effects, and any sustained-FPS
number need real hardware; the official Arch mirrors are unreachable from this
sandbox (only npm, PyPI and GitHub are). `scripts/capture-screenshots.sh` and a
flash-to-USB run are what close that, per the README.
