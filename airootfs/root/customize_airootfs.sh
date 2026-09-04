#!/usr/bin/env bash
# airootfs/root/customize_airootfs.sh
#
# archiso runs this once, inside the chroot, during the ISO build — then deletes
# it automatically. It is the only hook that runs with write access to the
# future root filesystem at build time.
#
# ============================================================================
# SECURITY: WHY THE PASSWORD IS NO LONGER IN THIS FILE
# ============================================================================
# This script used to pipe a literal, hardcoded root password into chpasswd and
# commit it to a public repository. The specific string is deliberately not
# repeated here - a credential stays compromised whether or not you keep
# writing it down, and echoing it into comments just spreads the copy around.
#
# That is not a "placeholder you should remember to change". A secret committed
# to a public repo is public from the moment it is pushed, forever — it stays in
# every clone, every fork, every mirror and in GitHub's object store even after
# the line is deleted. Rewriting history does not help, because the ISOs built
# from the old commit are already in the wild with that credential, and anyone
# who ever downloaded one of them now has a password that works on your machine.
#
# What this file does instead:
#   1. If airootfs/etc/marcus/root-password-hash exists at build time, its
#      contents are installed as root's shadow hash and the file is deleted from
#      the image. The hash never lives in git (see .gitignore); generate it with
#      scripts/set-root-password.sh, which reads the password from a prompt
#      rather than from argv or the environment.
#   2. Otherwise the root password is CLEARED, which is exactly what upstream
#      archiso does for its own live ISOs: you log in as root with no password,
#      because a live installer image is not a security boundary and a shared
#      well-known password is strictly worse than none.
#
# If you built an ISO from a commit that contained the old hardcoded password,
# treat that string as compromised: change it on every machine you flashed, and
# rotate anything else you reused it on.
#
# NOTE ON THIS MECHANISM: upstream archiso prints
# "customize_airootfs.sh is deprecated! Support for it will be removed in a
# future archiso version" when it runs this — it still works today, this isn't a
# mistake, but it isn't the long-term-correct approach. The ArchWiki-recommended
# replacement is a hashed entry directly in airootfs/etc/shadow. The hash-file
# path above is deliberately structured so that migrating is a one-line change:
# stop generating airootfs/etc/marcus/root-password-hash and instead write
# airootfs/etc/shadow.
set -euo pipefail

HASH_FILE="/etc/marcus/root-password-hash"

if [[ -s "$HASH_FILE" ]]; then
    # usermod -p takes an already-crypted hash, so the plaintext never touches
    # this file, the build log, or the image.
    usermod --password "$(cat "$HASH_FILE")" root
    # Do not ship the hash inside the ISO. It would be readable by anyone who
    # mounts the squashfs, which defeats the point of hashing it.
    rm -f "$HASH_FILE"
    rmdir /etc/marcus 2>/dev/null || true
    echo "customize_airootfs: installed root password hash from build-time file"
else
    # Live-image default: no root password, same as stock archiso.
    passwd -d root >/dev/null
    echo "customize_airootfs: no root password hash supplied — root password cleared (live-ISO default)"
    echo "customize_airootfs: to bake one in, run scripts/set-root-password.sh on the build host before building"
fi

# Timezone: a fresh archiso live image defaults to UTC. This affects more
# than the waybar clock — file timestamps, `date`, systemd/journal logs, all
# of it. Two more independent guarantees exist for the same reason:
#   * waybar's clock module gets an explicit "timezone": "Asia/Kolkata" override
#     in airootfs/root/.config/waybar/config, because there is a known class of
#     bug where waybar's C++ time-formatting library shows UTC even when the
#     system timezone is correct;
#   * ~/.zprofile exports TZ=Asia/Kolkata before `exec sway`, so the session
#     stays in IST even if /etc/localtime is ever not writable.
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
printf '%s\n' 'Asia/Kolkata' > /etc/timezone

# The user-directory skeleton. ~/Pictures in particular is not cosmetic: grim
# opens its output file directly, so the Print keybinding silently does nothing
# without it. xdg-user-dirs is in packages.x86_64.
mkdir -p /root/{Desktop,Documents,Downloads,Music,Pictures,Videos,Templates,Public}
command -v xdg-user-dirs-update >/dev/null 2>&1 && xdg-user-dirs-update || true
chown -R root:root /root

# zram-generator ships the generator binary but not an active configuration;
# the file in airootfs/etc/systemd/ is what actually creates zram0. Nothing to
# do here — this comment exists so the two files are found together.

# Build the plocate database for the live environment's own filesystem. The
# per-user home-directory index that spotlight.sh builds at runtime is separate
# and is rebuilt on first use.
command -v updatedb >/dev/null 2>&1 && updatedb || true
