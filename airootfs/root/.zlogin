# ~/.zlogin
#
# Sourced by zsh for login shells AFTER .zshrc. Stock archiso ships this file
# verbatim; the two lines below are unmodified from upstream.

# fix for screen readers
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

# Upstream archiso calls this unconditionally, because upstream archiso also
# ships airootfs/root/.automated_script.sh (it reads a `script=` kernel
# parameter and runs it - that's how the automated-install path works).
#
# THIS REPO DOES NOT SHIP THAT FILE. Only .zlogin was copied over from the
# archiso skeleton, so the call resolved to nothing and every single login
# shell - including the one that auto-starts sway on tty1 - printed
# "zsh: no such file or directory: /root/.automated_script.sh" before doing
# anything else. Guarding it costs nothing and keeps the file compatible with
# the upstream profile if the script is ever added back.
[[ -x ~/.automated_script.sh ]] && ~/.automated_script.sh

# Always succeed: .zlogin's exit status becomes the login shell's, and a
# trailing `[[ -x ... ]] && ...` that evaluates false would otherwise make the
# shell look like it failed.
true
