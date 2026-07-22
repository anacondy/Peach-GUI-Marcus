if [ -z "${WAYLAND_DISPLAY}" ] && [ "${XDG_VTNR}" -eq 1 ]; then
    if systemd-detect-virt --quiet; then
        export WLR_RENDERER=pixman
        export WLR_NO_HARDWARE_CURSORS=1
    fi
    exec sway
fi
