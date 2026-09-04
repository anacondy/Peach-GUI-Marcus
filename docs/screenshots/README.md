# Real screenshots

This directory is intentionally empty in the repository. Real screenshots require a
booted Marcus Mix session: a Wayland socket, a compositor and `wlr-screencopy`.
No CI container or build sandbox has that, so they are captured on the target.

From inside a running Marcus Mix session:

    scripts/capture-screenshots.sh

It writes `01-desktop.png`, `02-terminal-and-files.png`, `03-spotlight.png` and
`04-topbar.png` here and prints a reminder to commit them.

Until then, the README shows faithful *rendered previews* in `../previews/`,
generated from the repository's own config and CSS by
`../../tools/render-preview.mjs`. Those are labelled as previews and are not
screenshots.
