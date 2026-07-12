# Peach-GUI-Marcus

Welcome to the **Peach-GUI-Marcus** project. This repository contains the live, functional configurations for an Archiso-based Linux build featuring a highly customized Sway desktop environment. 

## System Status: Real vs. Decorative
Everything in this configuration is a **real, functional desktop environment**—not a mockup.
* Dock icons launch actual applications (`pcmanfm`, `firefox`, `kitty`).
* The taskbar (`wlr/taskbar`) accurately tracks open windows.
* `fastfetch` queries live hardware natively.
* `Alt+Space` performs live file searches via `plocate`.

**The SwayFX Hardware Caveat:**
Rounded corners, blur, and shadows require **SwayFX**. These effects will *not* render inside a Virtual Machine running the software-based `pixman` renderer. You must deploy this ISO to the actual target hardware (e.g., HP 14s) to experience the full immersive visual integration. All other functionality (docks, search, fastfetch) operates normally in VMs under vanilla Sway.

## File Structure & Updates

| Component | Description | Last Updated |
|---|---|---|
| `packages.x86_64` | Base lists + `zsh`, `grml-zsh-config`, `plocate`, `jq`, `firefox`, `pcmanfm` | 12-Jul-2026 |
| `...sway/config` | Unified SwayFX config with scaling and spotlight additions | 12-Jul-2026 |
| `...waybar/config` | Fixed top-bar (12-hour clock, correct paths) | 12-Jul-2026 |
| `...waybar/style.css` | Immersive dark and frosted glass styling matching the system theme | 12-Jul-2026 |
| `...waybar/dock.jsonc` & `.css` | App dock (Editor now safely launches `kitty nvim`) | 12-Jul-2026 |
| `...fastfetch/config.jsonc` | Marcus Mix–branded fastfetch using live system metrics | 12-Jul-2026 |
| `...root/.zshrc.local` | Sourced by `grml-zsh-config` to run `fastfetch` on terminal launch | 12-Jul-2026 |
| `...gtk-3.0/4.0/settings.ini` | Forces `MarcusMix` as the global icon theme | 12-Jul-2026 |
| `customize_airootfs.sh` | Bakes real root password into the build via `chpasswd` | 12-Jul-2026 |

## System Mechanics

### Root Password Handling
The script `customize_airootfs.sh` uses `chpasswd` to inject `root:marcus2026` into the build. **This is a temporary placeholder—change it.** While upstream archiso deprecates this in favor of direct `etc/shadow` hash edits, this method is used temporarily to avoid dependency on exact shadow file states. 

### ZSH & Fastfetch Automation
Terminal startup sequences rely strictly on `zsh` combined with `grml-zsh-config`. The `grml` framework automatically sources `~/.zshrc.local` on startup, which is what allows the customized `fastfetch` module to execute seamlessly upon opening a new terminal.

## Pre-Build Checklist (Required Core Files)
This repository focuses on frontend deployment. You must manually copy the core Archiso engine files from your legacy `marcus-mix-configs` repository to the root of this project before building:
* `profiledef.sh`
* `pacman.conf`
* `build-test-iso.sh`
* `bootstrap_packages`
* `vm-test.x86_64`

## Pending Milestones
The following deep-system tuning metrics remain untouched and are queued for future phases:
* Wine/Proton staging and validation
* Deep FPS/Hz kernel tuning
* OBS Studio and DaVinci Resolve rendering tests
* Verification of background daemons (`ananicy-cpp`, `power-profiles-daemon`)

## Build & Test Instructions

1. **Merge Core Files:** Ensure the five core engine files listed above are in the project root.
2. **Sync & Pull:** Commit your changes, push to GitHub, and run `git pull` in your WSL build environment.
3. **Build & VM Verification:** Compile the ISO and boot the VM. Verify that dock icons run, `Alt+Space` opens wofi/plocate, and terminals spawn the custom fastfetch. Log into Sway using the baked-in password.
4. **Hardware Deployment:** Flash to USB and boot on the actual HP 14s to test SwayFX visual modifiers (blur/shadows/rounding) and hardware-specific modules (WiFi/BT/Battery).