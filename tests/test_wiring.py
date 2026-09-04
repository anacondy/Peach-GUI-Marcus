"""Binary -> package wiring.

Every command this desktop invokes has to be provided by something in
packages.x86_64, otherwise it works on the developer's machine and silently does
nothing on the ISO. This is the check that catches `notify-send` being used in
three places while libnotify only ever arrived as a transitive dependency.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jsonc  # noqa: E402
from _harness import main  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AIROOTFS = os.path.join(ROOT, "airootfs")

# binary -> Arch package. Entries whose package is in `base` are listed as
# "base" so the intent is visible; the assertion only cares that the package is
# either base or explicitly listed.
BIN_PKG = {
    "sway": "sway", "swaymsg": "sway", "swaynag": "sway",
    "swaybg": "swaybg", "swaylock": "swaylock", "swayidle": "swayidle",
    "waybar": "waybar", "wofi": "wofi",
    "mako": "mako", "makoctl": "mako",
    "kitty": "kitty",
    "pcmanfm": "pcmanfm", "firefox": "firefox",
    "grim": "grim", "slurp": "slurp",
    "brightnessctl": "brightnessctl",
    "wpctl": "wireplumber",
    "playerctl": "playerctl",
    "wl-paste": "wl-clipboard", "wl-copy": "wl-clipboard",
    "cliphist": "cliphist",
    "jq": "jq",
    "plocate": "plocate", "updatedb": "plocate",
    "xdg-open": "xdg-utils",
    "notify-send": "libnotify",
    "gio": "gvfs",
    "xdg-user-dirs-update": "xdg-user-dirs",
    "polkit-gnome-authentication-agent-1": "polkit-gnome",
    "fastfetch": "fastfetch",
    "nvim": "neovim",
    "systemd-detect-virt": "base",
    "bash": "base", "sh": "base", "awk": "base", "sed": "base", "grep": "base",
    "find": "base", "head": "base", "cut": "base", "basename": "base",
    "mktemp": "base", "date": "base", "mkdir": "base", "cat": "base",
    "mv": "base", "rm": "base", "ls": "base", "id": "base", "tr": "base",
    "setsid": "base", "pgrep": "base", "pkill": "base", "kill": "base",
    "tar": "base", "sudo": "sudo",
    # plocate installs the `locate` name too; spotlight.sh accepts either.
    "locate": "plocate",
}

# Commands that are optional by design: the caller degrades if they are absent.
OPTIONAL = {
    "hostname", "mokutil", "gpg", "cryptsetup", "lsblk", "findmnt",
    "ldconfig", "openssl", "ssh", "ssh-keygen", "pacman", "makepkg", "curl",
    "mkarchiso", "zramctl", "vulkaninfo", "vkcube", "swapon",
}


def _read(p):
    with open(p, encoding="utf-8") as fh:
        return fh.read()


def packages():
    out = set()
    for line in _read(os.path.join(ROOT, "packages.x86_64")).splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            out.add(line)
    return out


def referenced_commands():
    """(source, binary) for every command the desktop can try to run."""
    refs = []

    sway_cfg = _read(os.path.join(AIROOTFS, "root/.config/sway/config"))
    for m in re.findall(r"^\s*(?:exec|exec_always)\s+(.+)$", sway_cfg, re.M):
        # `mkdir -p X && grim Y && notify-send Z` is three commands, not one.
        for part in re.split(r"&&|\|\||\|", m):
            words = part.strip().split()
            if not words:
                continue
            word = words[0]
            # Skip sway-internal things and variable expansions.
            if word.startswith("$") or word.endswith(".sh"):
                continue
            refs.append(("sway/config", os.path.basename(word)))

    for name in ("config", "dock.jsonc"):
        cfg = jsonc.load(os.path.join(AIROOTFS, "root/.config/waybar", name))
        for mod, sub in cfg.items():
            if not isinstance(sub, dict):
                continue
            for key, val in sub.items():
                if key.startswith("on-") and isinstance(val, str):
                    # waybar's wlr/taskbar takes built-in ACTIONS on its click
                    # bindings (activate, minimize, maximize, close), not shell
                    # commands. Anything else is a command.
                    if mod == "wlr/taskbar" and val in (
                            "activate", "minimize", "maximize", "close"):
                        continue
                    words = re.split(r"&&|\|\||\|", val)[0].strip().split()
                    if words:
                        refs.append((f"waybar/{name}:{mod}.{key}",
                                     os.path.basename(words[0])))

    for dirpath, _d, files in os.walk(os.path.join(AIROOTFS, "root")):
        for f in files:
            full = os.path.join(dirpath, f)
            rel = os.path.relpath(full, ROOT)
            for lineno, line in enumerate(_read(full).splitlines(), 1):
                s = line.strip()
                if s.startswith("#"):
                    continue
                for m in re.finditer(r"command -v ([a-zA-Z0-9_.-]+)", line):
                    refs.append((f"{rel}:{lineno}", m.group(1)))
    return refs


def test_every_referenced_binary_has_a_package():
    pkgs = packages()
    missing = []
    unmapped = []
    seen = set()
    for source, binary in referenced_commands():
        if binary in seen:
            continue
        seen.add(binary)
        if binary in OPTIONAL:
            continue
        pkg = BIN_PKG.get(binary)
        if pkg is None:
            unmapped.append(f"{source}: {binary} (not in the binary->package map)")
            continue
        if pkg == "base" or pkg in pkgs:
            continue
        missing.append(f"{source}: {binary} needs {pkg}, absent from packages.x86_64")
    assert not missing, "commands with no providing package:\n    " + "\n    ".join(missing)
    assert not unmapped, \
        "commands this test does not know about (extend BIN_PKG):\n    " + "\n    ".join(unmapped)


def test_no_package_listed_twice():
    lines = [l.strip() for l in _read(os.path.join(ROOT, "packages.x86_64")).splitlines()]
    pkgs = [l for l in lines if l and not l.startswith("#")]
    dupes = sorted({p for p in pkgs if pkgs.count(p) > 1})
    assert not dupes, f"duplicate packages in packages.x86_64: {dupes}"


def test_profiledef_paths_exist_in_airootfs():
    text = _read(os.path.join(ROOT, "profiledef.sh"))
    # Paths that come from the stock archiso profile and are created by
    # mkarchiso/pacman-key during the build rather than shipped from airootfs.
    # They are correct to list even though they do not exist in this repo.
    generated = {"/root", "/root/.gnupg", "/etc/shadow",
                 "/usr/local/bin/choose-mirror",
                 "/usr/local/bin/Installation_guide",
                 "/usr/local/bin/livecd-sound"}
    # Deliberately NOT in that set: /root/.automated_script.sh. It is not
    # archiso-generated, it is shipped by the upstream releng profile, and this
    # repo does not ship it - so the entry was removed from profiledef.sh and
    # this test is what keeps it out.
    missing = []
    # Skip comment lines: profiledef.sh documents removed entries verbatim, and
    # those must not be read as live assertions.
    code = "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))
    for path in re.findall(r'\["(/[^"]+)"\]="\d+:\d+:\d+"', code):
        if path in generated:
            continue
        # /etc/shadow, /usr/local/bin/* are created by archiso itself; only
        # assert on the ones this repo actually owns.
        if not (path.startswith("/root/") or path.startswith("/usr/share/icons/")):
            continue
        if not os.path.exists(os.path.join(AIROOTFS, path.lstrip("/"))):
            missing.append(path)
    assert not missing, \
        "profiledef.sh file_permissions entries with no file in airootfs " \
        f"and no archiso-generated equivalent:\n    " + "\n    ".join(missing)


def test_zlogin_does_not_run_a_missing_script():
    """`.zlogin` called ~/.automated_script.sh unconditionally.

    Upstream archiso ships that file; this repo only copied .zlogin, so every
    login shell printed 'no such file or directory' before starting sway.
    """
    text = _read(os.path.join(AIROOTFS, "root/.zlogin"))
    shipped = os.path.isfile(os.path.join(AIROOTFS, "root/.automated_script.sh"))
    for lineno, line in enumerate(text.splitlines(), 1):
        s = line.strip()
        if s.startswith("#") or "automated_script.sh" not in s:
            continue
        assert shipped or "-x" in s or "-f" in s, \
            f".zlogin:{lineno} runs a script that is not shipped and is not guarded"


def test_every_airootfs_file_is_listed_or_default():
    """Nothing under airootfs/usr/share should be silently unreadable."""
    bad = []
    for dirpath, _d, files in os.walk(os.path.join(AIROOTFS, "usr")):
        for f in files:
            full = os.path.join(dirpath, f)
            if not os.access(full, os.R_OK):
                bad.append(os.path.relpath(full, ROOT))
    assert not bad, f"unreadable files in airootfs/usr: {bad}"


TESTS = [
    test_every_referenced_binary_has_a_package,
    test_no_package_listed_twice,
    test_profiledef_paths_exist_in_airootfs,
    test_zlogin_does_not_run_a_missing_script,
    test_every_airootfs_file_is_listed_or_default,
]

if __name__ == "__main__":
    main(TESTS)
