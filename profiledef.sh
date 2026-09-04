#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="marcus mix"
iso_label="ARCH_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Arch Linux <https://archlinux.org>"
iso_application="Arch Linux Live/Rescue DVD"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  # NOTE: the upstream releng profile also lists
  #   ["/root/.automated_script.sh"]="0:0:755"
  # and ships airootfs/root/.automated_script.sh alongside it. This repo copied
  # .zlogin from the skeleton but not that script, so the entry was dead and has
  # been removed. If you ever add the script back, re-add the permission here -
  # tests/test_wiring.py fails if a listed path does not exist, so it will tell
  # you either way.
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  ["/root/customize_airootfs.sh"]="0:0:755"
  ["/root/.config/sway/scripts/auto-scale.sh"]="0:0:755"
  ["/root/.config/sway/scripts/spotlight.sh"]="0:0:755"
  ["/root/.config/sway/scripts/perf-profile.sh"]="0:0:755"
  ["/root/.config/sway/scripts/start-dock.sh"]="0:0:755"
)

