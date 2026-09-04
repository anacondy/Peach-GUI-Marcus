"""Static validation of the desktop configs.

These are the checks that catch the class of bug this repo actually keeps
having: a config that parses fine but references something that isn't there.
A waybar module listed in modules-right with no config object, a format string
using a token the module never substitutes, a CSS url() pointing at an SVG that
was renamed, a font named in three places and installed in none.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jsonc  # noqa: E402
from _harness import main  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AIROOTFS = os.path.join(ROOT, "airootfs")
WAYBAR = os.path.join(AIROOTFS, "root/.config/waybar")
SWAY = os.path.join(AIROOTFS, "root/.config/sway")


def _read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def packages():
    pkgs = set()
    for line in _read(os.path.join(ROOT, "packages.x86_64")).splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        pkgs.add(line)
    return pkgs


# ---------------------------------------------------------------------------
# waybar
# ---------------------------------------------------------------------------
# Tokens each module actually substitutes. Anything else is rendered literally,
# which is invisible unless you are staring at the bar - the memory module spent
# its whole life printing "RAM {}%" for exactly this reason.
TOKENS = {
    "clock": set(),  # strftime/chrono specifiers, not waybar tokens
    "cpu": {"usage"},
    "memory": {"percentage", "total", "used", "avail", "maxUsed",
               "swapTotal", "swapUsed", "swapPercentage"},
    "battery": {"capacity", "icon", "time", "power"},
    "pulseaudio": {"volume", "icon", "desc", "format_source"},
    "network": {"essid", "ipaddr", "ifname", "signalStrength", "frequency",
                "netmask", "gateway"},
    "tray": set(),
    "sway/workspaces": {"name", "icon"},
    "wlr/taskbar": {"name", "title", "app_id", "icon", "index", "state"},
}
# Modules that need no config object at all.
NO_CONFIG_NEEDED = {"sway/workspaces", "sway/mode", "sway/window", "tray",
                    "idle_inhibitor", "sway/scratchpad"}

FORMAT_RE = re.compile(r"\{([^{}]*)\}")
TOKEN_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)(?::[^}]*)?$")


def _walk_strings(node):
    if isinstance(node, dict):
        for v in node.values():
            yield from _walk_strings(v)
    elif isinstance(node, list):
        for v in node:
            yield from _walk_strings(v)
    elif isinstance(node, str):
        yield node


def test_waybar_configs_parse():
    for name in ("config", "dock.jsonc"):
        cfg = jsonc.load(os.path.join(WAYBAR, name))
        assert isinstance(cfg, dict), f"{name} did not parse to an object"


def test_waybar_modules_have_config():
    cfg = jsonc.load(os.path.join(WAYBAR, "config"))
    missing = []
    for side in ("modules-left", "modules-center", "modules-right"):
        for mod in cfg.get(side, []):
            if mod in NO_CONFIG_NEEDED:
                continue
            if mod not in cfg:
                missing.append(f"{side}:{mod}")
    assert not missing, f"waybar modules with no config object: {missing}"


def test_waybar_format_tokens_are_real():
    bad = []
    for name in ("config", "dock.jsonc"):
        cfg = jsonc.load(os.path.join(WAYBAR, name))
        for mod, sub in cfg.items():
            if not isinstance(sub, dict):
                continue
            allowed = TOKENS.get(mod)
            for key, val in sub.items():
                if not key.startswith("format") or not isinstance(val, str):
                    continue
                for raw in FORMAT_RE.findall(val):
                    if raw.startswith(":"):
                        continue  # strftime/chrono specifier
                    m = TOKEN_RE.match(raw)
                    if m is None:
                        bad.append(f"{name}:{mod}.{key} -> '{{{raw}}}' is not a token")
                        continue
                    if allowed is not None and m.group(1) not in allowed:
                        bad.append(
                            f"{name}:{mod}.{key} -> '{m.group(1)}' is not a "
                            f"{mod} token (valid: {sorted(allowed)})")
    assert not bad, "invalid waybar format tokens:\n    " + "\n    ".join(bad)


def test_waybar_no_empty_icons():
    """An empty string in format-icons renders as nothing at all.

    Both the battery and the pulseaudio modules shipped like this: the arrays
    were ['','','',''] and {'default':['','','']}, so the bar showed a percentage
    and a gap where an icon should have been.
    """
    cfg = jsonc.load(os.path.join(WAYBAR, "config"))
    empty = []
    for mod, sub in cfg.items():
        if not isinstance(sub, dict) or "format-icons" not in sub:
            continue
        icons = sub["format-icons"]
        flat = icons if isinstance(icons, list) else list(icons.values())
        for entry in flat:
            for glyph in (entry if isinstance(entry, list) else [entry]):
                if glyph == "":
                    empty.append(mod)
    assert not empty, f"modules with empty format-icons glyphs: {sorted(set(empty))}"


def test_waybar_clock_is_ist_and_dmy():
    cfg = jsonc.load(os.path.join(WAYBAR, "config"))
    clock = cfg["clock"]
    assert clock.get("timezone") == "Asia/Kolkata", \
        f"clock.timezone is {clock.get('timezone')!r}, expected Asia/Kolkata"
    tip = clock.get("tooltip-format", "")
    assert "%d %B %Y" in tip, \
        f"tooltip-format {tip!r} is not Day-Month-Year (want '%d %B %Y')"


def test_waybar_pua_glyphs_have_a_font():
    """Private-use codepoints need an icon font installed or they draw boxes."""
    cfg = jsonc.load(os.path.join(WAYBAR, "config"))
    used = [s for s in _walk_strings(cfg) if any("\ue000" <= ch <= "\uf8ff" for ch in s)]
    assert used, "expected battery/volume icons to use Font Awesome codepoints"
    pkgs = packages()
    assert "ttf-font-awesome" in pkgs, \
        "configs use Font Awesome codepoints but ttf-font-awesome is not in packages.x86_64"
    css = _read(os.path.join(WAYBAR, "style.css"))
    stack = re.search(r"font-family:([^;]+);", css).group(1)
    assert "Font Awesome" in stack, \
        "style.css font stack names JetBrains Mono alone; Pango will not fall back to the icon font"


# ---------------------------------------------------------------------------
# CSS assets
# ---------------------------------------------------------------------------
URL_RE = re.compile(r'url\(\s*"([^"]+)"\s*\)')


def test_css_urls_resolve():
    missing = []
    for css in ("style.css", "dock.css"):
        text = _read(os.path.join(WAYBAR, css))
        for url in URL_RE.findall(text):
            if not url.startswith("/"):
                continue
            # The absolute path is how it appears in the built image; in the repo
            # it lives under airootfs/.
            repo_path = os.path.join(AIROOTFS, url.lstrip("/"))
            if not os.path.isfile(repo_path):
                missing.append(f"{css}: {url}")
    assert not missing, "CSS url() targets not found in airootfs:\n    " + "\n    ".join(missing)


FONT_PACKAGES = {
    "JetBrains Mono": "ttf-jetbrains-mono",
    "Font Awesome 6 Free": "ttf-font-awesome",
    "Font Awesome 5 Free": "ttf-font-awesome",
    "DejaVu Sans": "ttf-dejavu",
    "Noto Sans Symbols 2": "noto-fonts",
}


def test_named_fonts_are_installed():
    """Every primary font named by the configs must actually be in the ISO.

    'JetBrains Mono' was named in waybar/style.css, waybar/dock.css and the sway
    `font pango:` line, and ttf-jetbrains-mono was absent from packages.x86_64,
    so nothing in the desktop ever rendered in it.
    """
    pkgs = packages()
    specs = []
    for css in ("style.css", "dock.css"):
        for stack in re.findall(r"font-family:([^;]+);", _read(os.path.join(WAYBAR, css))):
            first = stack.split(",")[0].strip().strip('"').strip("'")
            specs.append((css, first))
    sway_cfg = _read(os.path.join(SWAY, "config"))
    for m in re.findall(r"^\s*font\s+pango:(.+)$", sway_cfg, re.M):
        specs.append(("sway/config", m.strip().rsplit(" ", 1)[0]))

    uninstalled = []
    for where, family in specs:
        pkg = FONT_PACKAGES.get(family)
        if pkg is None:
            uninstalled.append(f"{where}: unknown font {family!r}")
        elif pkg not in pkgs:
            uninstalled.append(f"{where}: {family!r} needs {pkg}, not in packages.x86_64")
    assert not uninstalled, "\n    " + "\n    ".join(uninstalled)


# ---------------------------------------------------------------------------
# sway
# ---------------------------------------------------------------------------
SWAYFX_ONLY = ("corner_radius", "smart_corner_radius", "blur", "blur_xray",
               "blur_passes", "blur_radius", "blur_noise", "blur_brightness",
               "blur_contrast", "blur_saturation", "shadows", "shadows_on_csd",
               "shadow_blur_radius", "shadow_color", "shadow_offset",
               "default_dim_inactive", "dim_inactive_colors.unfocused",
               "layer_effects", "titlebar_separator")


def test_swayfx_directives_are_not_inline():
    """SwayFX directives must live in the generated include.

    packages.x86_64 installs vanilla sway. SwayFX is AUR-only and archiso cannot
    install AUR packages, so every one of these directives makes sway log
    'Unknown/invalid command' on each config load. They now live in
    effects.conf, which perf-profile.sh fills in only when SwayFX is present.
    """
    offenders = []
    for lineno, line in enumerate(_read(os.path.join(SWAY, "config")).splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        head = stripped.split()[0]
        if head in SWAYFX_ONLY:
            offenders.append(f"config:{lineno}: {head}")
    assert not offenders, \
        "SwayFX-only directives found inline (they must be in effects.conf):\n    " \
        + "\n    ".join(offenders)
    assert "include ~/.config/sway/effects.conf" in _read(os.path.join(SWAY, "config")), \
        "sway config no longer includes the generated effects.conf"


def test_sway_no_duplicate_daemons():
    """exec_always must not launch a long-lived daemon directly.

    `exec_always` re-runs on every `swaymsg reload` and does not stop the
    previous instance, so `exec_always waybar ...` stacked a second dock on top
    of the first on every reload. Daemons go through a wrapper that kills the
    old one first.
    """
    bad = []
    for lineno, line in enumerate(_read(os.path.join(SWAY, "config")).splitlines(), 1):
        stripped = line.strip()
        if not stripped.startswith("exec_always"):
            continue
        cmd = stripped[len("exec_always"):].strip()
        first = cmd.split()[0] if cmd else ""
        if first.endswith(".sh"):
            continue
        bad.append(f"config:{lineno}: exec_always {cmd!r}")
    assert not bad, \
        "exec_always launching a bare daemon (duplicates on every reload):\n    " \
        + "\n    ".join(bad)


def test_sway_screenshot_paths_are_created():
    """grim fopen()s its output path; a missing ~/Pictures fails silently."""
    cfg = _read(os.path.join(SWAY, "config"))
    for lineno, line in enumerate(cfg.splitlines(), 1):
        if "grim " in line and "bindsym" in line:
            assert "mkdir -p" in line, \
                f"config:{lineno}: grim writes into a directory it does not create"


def test_sway_scripts_exist_and_are_executable_intents():
    cfg = _read(os.path.join(SWAY, "config"))
    missing = []
    for cmd in re.findall(r"exec(?:_always)?\s+(\S+\.sh)", cfg):
        path = cmd.replace("~/.config/sway/", os.path.join(SWAY, "") + "/")
        path = os.path.normpath(path)
        if not os.path.isfile(path):
            missing.append(cmd)
    assert not missing, f"sway execs scripts that do not exist: {missing}"


# ---------------------------------------------------------------------------
# profiledef / secrets
# ---------------------------------------------------------------------------
def test_profiledef_covers_every_root_script():
    text = _read(os.path.join(ROOT, "profiledef.sh"))
    listed = set(re.findall(r'\["(/root/[^"]+)"\]="0:0:(\d+)"', text))
    listed_exec = {p for p, mode in listed if mode == "755"}
    missing = []
    for dirpath, _dirs, files in os.walk(os.path.join(AIROOTFS, "root")):
        for f in files:
            full = os.path.join(dirpath, f)
            if not (f.endswith(".sh") or f == "customize_airootfs.sh"):
                continue
            rel = "/root/" + os.path.relpath(full, os.path.join(AIROOTFS, "root"))
            if rel not in listed_exec:
                missing.append(rel)
    assert not missing, \
        "scripts in airootfs/root without a 0:0:755 entry in profiledef.sh " \
        f"(they land in the ISO without the execute bit):\n    " + "\n    ".join(sorted(missing))


# (pattern, label, code_only)
# code_only patterns are matched against non-comment lines only, so prose that
# describes the fix cannot trip the alarm; the shadow-hash pattern still scans
# the whole file, because a leaked hash is leaked wherever it is written down.
SECRET_PATTERNS = [
    (r"\|\s*chpasswd\b", "password piped into chpasswd on a command line", True),
    (r"passwd\s+-p\s+\S", "passwd -p with an inline password", True),
    (r"usermod\s+(-p|--password)\s+['\"]?\$[16y]\$", "a shadow hash on a command line", True),
    (r"\$6\$[./A-Za-z0-9]{20,}", "a committed SHA-512 crypt hash", False),
    (r"\$y\$[./A-Za-z0-9]{20,}", "a committed yescrypt hash", False),
]


def _is_comment(line):
    s = line.lstrip()
    return s.startswith("#") or s.startswith("//")


def test_no_secrets_in_the_repo():
    """The regression test for the hardcoded root password.

    A live credential was committed to this repository's public history. A
    secret in a public repo is public forever - deleting the line does not
    un-leak it. This test exists so it cannot come back.
    """
    hits = []
    for dirpath, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in
                   (".git", "out", "work", ".arena", "__pycache__", "tests", "docs")]
        for f in files:
            if f.endswith((".png", ".jpg", ".svg")):
                continue
            full = os.path.join(dirpath, f)
            try:
                text = _read(full)
            except (UnicodeDecodeError, OSError):
                continue
            rel = os.path.relpath(full, ROOT)
            # README/ANALYSIS are allowed to describe the leak in prose.
            if rel in ("README.md", "ANALYSIS.md"):
                continue
            lines = text.splitlines()
            for pattern, label, code_only in SECRET_PATTERNS:
                for idx, line in enumerate(lines, 1):
                    if code_only and _is_comment(line):
                        continue
                    if re.search(pattern, line):
                        hits.append(f"{rel}:{idx}: {label}")
    assert not hits, "possible committed secret:\n    " + "\n    ".join(hits)


TESTS = [
    test_waybar_configs_parse,
    test_waybar_modules_have_config,
    test_waybar_format_tokens_are_real,
    test_waybar_no_empty_icons,
    test_waybar_clock_is_ist_and_dmy,
    test_waybar_pua_glyphs_have_a_font,
    test_css_urls_resolve,
    test_named_fonts_are_installed,
    test_swayfx_directives_are_not_inline,
    test_sway_no_duplicate_daemons,
    test_sway_screenshot_paths_are_created,
    test_sway_scripts_exist_and_are_executable_intents,
    test_profiledef_covers_every_root_script,
    test_no_secrets_in_the_repo,
]

if __name__ == "__main__":
    main(TESTS)
