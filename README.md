# Peach-GUI-Marcus — frontend + fixes, integrated

## Is the DE real or decorative? Real — with one honest caveat

Everything in this zip is actual sway/waybar/wofi/fastfetch configuration —
the same kind of file that already makes your *current* top waybar genuinely
live (your own screenshots proved that: 26%→22%→7% CPU actually moving).
None of it is a browser mockup. Once these files sit in the right place and
you rebuild:
- clicking a dock icon really runs `pcmanfm` / `firefox` / `kitty` / etc.
- the taskbar really shows your open windows (via `wlr/taskbar`)
- `fastfetch` really queries your live hardware — nothing here is faked
- Alt+Space really searches your real files via `plocate`

The one caveat, unchanged from before: rounded corners / blur / shadows need
**SwayFX**, not vanilla sway, and none of that renders under the VM's
`pixman` software renderer (your own `zprofile` forces that inside VMs on
purpose). You will only see the rounding/blur/shadow on the real HP 14s.
Everything else — dock clicks, taskbar, search, fastfetch — works under
vanilla sway too, VM included.

## Extract this correctly (the waybar folder bug, avoided this time)

Your other session's diagnosis of the doubled `airootfs/root/airootfs/root/`
path was right — that happens when you right-click the wrong folder in VS
Code's tree and it nests instead of landing at the top level.

**To avoid repeating it:** extract this zip so its contents land *directly*
in your repo root — `airootfs/`, `packages.x86_64` etc. should sit right
next to your existing `LICENSE`, not inside another folder. In PowerShell,
from inside `Peach-GUI-Marcus`:
```powershell
Expand-Archive -Path path\to\marcus-mix-frontend-v2.zip -DestinationPath . -Force
```
That extracts to the current directory directly — no manual folder creation
in the VS Code UI at all, which is what caused the nesting the first time.

## What's genuinely new or fixed in this drop

| File | What it is |
|---|---|
| `packages.x86_64` | Your list + `zsh`, `grml-zsh-config` (see below), `plocate`, `jq`, `firefox`, `pcmanfm` |
| `airootfs/root/.config/sway/config` | Your original config, merged with the SwayFX/scaling/spotlight/dock additions — one file, not a fragile `include` chain |
| `airootfs/root/.config/waybar/config` | The top-bar fix from your other session (12-hour clock etc.) — same content, correct path this time |
| `airootfs/root/.config/waybar/style.css` | **New** — this bar had zero custom CSS before (stock example styling); now matches the rest of the theme |
| `airootfs/root/.config/waybar/dock.jsonc` + `dock.css` | The app dock (dog centered). One change from last time: the editor button now runs `kitty nvim`, not `code` — VS Code isn't installed yet, so it would've silently done nothing on click |
| `airootfs/root/.config/fastfetch/config.jsonc` | Marcus Mix–branded fastfetch — real modules only, no mocked fields |
| `airootfs/root/.zshrc.local` | grml-zsh-config's own designated file for personal customizations (confirmed via grml's docs — this doesn't fight the managed grml zshrc). Runs `fastfetch` on every new interactive shell |
| `airootfs/root/customize_airootfs.sh` | Bakes a real root password into the build (see below) |
| `airootfs/root/.config/gtk-3.0/settings.ini`, `gtk-4.0/settings.ini` | Actually sets `MarcusMix` as the icon theme — mentioned last time, actually created now |
| `airootfs/usr/share/icons/MarcusMix/` | Unchanged from last time |
| `airootfs/root/.config/sway/scripts/*.sh` | Unchanged from last time |

## Password: baked in, with an honest note on the mechanism

`customize_airootfs.sh` runs once during the build (inside the chroot) and
sets `root:marcus2026` via `chpasswd` — **change that password**, it's a
placeholder. This mechanism is flagged deprecated by upstream archiso
(still functional, not yet removed) in favor of hand-editing a hashed entry
into `airootfs/etc/shadow`. I didn't do the direct-shadow-edit version
because I don't have your actual current shadow file content to safely
patch — `chpasswd` at build time sidesteps that by not needing to know it.
Worth migrating later; not urgent now.

## zsh / grml-zsh-config, confirmed

The other session's diagnosis was right, and I've made sure both packages
that fix it are in `packages.x86_64` — not just `zsh` but `grml-zsh-config`
too. That second one matters specifically for `.zshrc.local` to do anything:
it's grml's own zshrc that sources `~/.zshrc.local` automatically. Without
`grml-zsh-config` installed, a bare zsh wouldn't source that file at all, and
the fastfetch-on-new-terminal behavior would silently never fire.

## What you'll still need to bring over from marcus-mix-configs

I've never seen the actual contents of these files — only their names in a
screenshot — so I can't safely reconstruct them. Copy these over as-is from
your old repo: `profiledef.sh`, `pacman.conf`, `build-test-iso.sh`,
`bootstrap_packages`, `vm-test.x86_64`. Nothing in this zip touches or
replaces any of them.

## Not touched this round

The 20-goal scorecard from your other session is still accurate for
everything outside the DE/frontend: Wine/Proton, FPS/Hz tuning, OBS/DaVinci
testing, and confirming `ananicy-cpp`/`power-profiles-daemon` are actually
running are all still open, and weren't in scope here.

## After extracting

1. Copy over the five files listed above from your old repo
2. Commit, push, `git pull` in WSL, rebuild
3. Confirm in the VM: dock icons launch real apps, Alt+Space searches real
   files, `fastfetch` shows Marcus Mix branding on new terminals, root logs
   into swaylock with the password you set
4. Then the real test: the HP 14s itself, for the rounding/blur/shadow and
   for real WiFi/BT/battery/printer behavior the VM can't validate
