#!/usr/bin/env bash
# airootfs/root/customize_airootfs.sh
#
# archiso runs this once, inside the chroot, during the ISO build — then
# deletes it automatically. This is how to bake a real, permanent root
# password into the built image, instead of running `passwd` by hand every
# time you boot.
#
# NOTE ON THIS MECHANISM: upstream archiso currently prints
# "customize_airootfs.sh is deprecated! Support for it will be removed in a
# future archiso version" when it runs this — it still works today, this
# isn't a mistake, but it's not the long-term-correct approach. The
# ArchWiki-recommended replacement is a hashed entry directly in
# airootfs/etc/shadow (via `openssl passwd -6`). I didn't hand you that
# directly because I don't have your actual current shadow file content to
# safely edit — this script sidesteps that entirely by calling chpasswd at
# build time, which works correctly regardless of the file's exact prior
# contents. Worth migrating to the direct-shadow-edit approach yourself once
# this one gets removed upstream; not urgent today.
#
# CHANGE THIS PASSWORD — "marcus2026" is a placeholder, not a real credential.
echo "root:marcus2026" | chpasswd
