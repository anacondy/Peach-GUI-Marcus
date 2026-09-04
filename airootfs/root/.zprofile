# ~/.zprofile
#
# Sourced by zsh on a login shell, which is how you land on tty1 in the live
# image. This file is the ONLY correct place to set environment variables for
# the desktop: sway has no `setenv` command, and `export` inside a sway `exec`
# line affects only that one child shell, not the compositor's environment and
# therefore not any application you launch later.
#
# root's login shell has always been zsh - bash would never read .zprofile or
# .zlogin at all, which is what made tty1 go black when zsh got trimmed from
# packages.x86_64 during the RAM/bloat pass.

if [ -z "${WAYLAND_DISPLAY}" ] && [ "${XDG_VTNR}" -eq 1 ]; then

    # --- Wayland-native clients -----------------------------------------
    # Without these, GTK/Qt/Electron/Java apps fall back to XWayland, where they
    # are rendered at 1x into a scaled surface: visibly blurry text, and the
    # compositor pays for a second buffer copy plus a scale blit every frame.
    # That is the single largest avoidable performance loss in a fractional
    # scaling setup, and it costs nothing to fix.
    export XDG_CURRENT_DESKTOP=sway
    export XDG_SESSION_DESKTOP=sway
    export XDG_SESSION_TYPE=wayland
    export GDK_BACKEND=wayland
    export QT_QPA_PLATFORM=wayland
    export SDL_VIDEODRIVER=wayland
    export CLUTTER_BACKEND=wayland
    export MOZ_ENABLE_WAYLAND=1
    export ELECTRON_OZONE_PLATFORM_HINT=auto
    export _JAVA_AWT_WM_NONREPARENTING=1

    # --- Timezone ---------------------------------------------------------
    # Belt to customize_airootfs.sh's /etc/localtime symlink: if that ever stops
    # applying (a read-only root, a chroot, a container), the session still
    # comes up in Indian Standard Time rather than UTC.
    export TZ=Asia/Kolkata

    # --- VM vs real hardware ---------------------------------------------
    # pixman is wlroots' software renderer. It is the only thing that will run
    # under VirtualBox/QEMU without GPU passthrough, and it cannot do blur,
    # shadows or rounded corners at all - by design, not a bug.
    if systemd-detect-virt --quiet; then
        export WLR_RENDERER=pixman
        export WLR_NO_HARDWARE_CURSORS=1
    fi

    # --- Effects include, generated before the first config parse ---------
    # Must happen before `exec sway`: the sway config `include`s this file, and
    # running perf-profile only from within sway would mean the first frame is
    # parsed with no effects file at all.
    if [ -x "$HOME/.config/sway/scripts/perf-profile.sh" ]; then
        "$HOME/.config/sway/scripts/perf-profile.sh" --prestart 2>/dev/null || true
    fi

    exec sway
fi
