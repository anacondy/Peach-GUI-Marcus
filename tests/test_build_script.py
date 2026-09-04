"""Functional test for scripts/build-test-iso.sh.

Runs the REAL script. `mkarchiso` and `sudo` are replaced with stubs on PATH;
everything else - the path resolution, the profile staging, the package merge,
the cleanup trap - is the shipped code doing its actual work.

This is the test that would have caught the bug both branches shipped: the
script resolved its profile directory as `dirname $0`, which after the move into
scripts/ pointed at scripts/ instead of the repository root, so it died on
`cp: cannot stat '.../scripts/packages.x86_64'` before mkarchiso ever ran.
"""
import hashlib
import os
import shutil
import stat
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _harness import main  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "scripts/build-test-iso.sh")


class Result:
    def __init__(self, **kw):
        self.__dict__.update(kw)


_CACHE = {}


def run_build():
    """Invoke the build script once and memoise what it did.

    Every assertion below inspects a different property of the same run, and the
    script is slow enough (it tars the whole profile) that repeating it seven
    times buys nothing.
    """
    if "result" in _CACHE:
        return _CACHE["result"]

    tmp = tempfile.mkdtemp(prefix="build-test.")
    _CACHE["tmp"] = tmp
    log = os.path.join(tmp, "mkarchiso.log")

    # Stub mkarchiso: record the profile directory it was handed and snapshot
    # the whole staged profile, because the script's EXIT trap deletes the real
    # staging directory the moment it returns.
    fake = os.path.join(tmp, "mkarchiso")
    with open(fake, "w", encoding="utf-8") as fh:
        fh.write(f"""#!/bin/bash
printf '%s\\n' "$@" > "{log}"
profile="${{@: -1}}"
cp -a "$profile" "{tmp}/staged-profile"
cp "$profile/packages.x86_64" "{tmp}/packages.seen"
exit 0
""")
    # Stub sudo: we are not root, so the script prefixes mkarchiso with it.
    fake_sudo = os.path.join(tmp, "sudo")
    with open(fake_sudo, "w", encoding="utf-8") as fh:
        fh.write('#!/bin/bash\nexec "$@"\n')
    for f in (fake, fake_sudo):
        os.chmod(f, os.stat(f).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

    pkg = os.path.join(ROOT, "packages.x86_64")
    before = hashlib.sha256(open(pkg, "rb").read()).hexdigest()

    env = dict(os.environ)
    env["PATH"] = tmp + os.pathsep + env["PATH"]
    env["OUT_DIR"] = os.path.join(tmp, "out")
    proc = subprocess.run(["bash", SCRIPT], env=env, capture_output=True,
                          text=True, cwd=tmp, timeout=180)

    profile = None
    packages_seen = []
    if os.path.isfile(log):
        args = open(log, encoding="utf-8").read().split()
        if args:
            # Point the assertions at the preserved copy, not the deleted stage.
            profile = os.path.join(tmp, "staged-profile")
            _CACHE["profile_arg"] = args[-1]
    seen_path = os.path.join(tmp, "packages.seen")
    if os.path.isfile(seen_path):
        packages_seen = [l.strip() for l in open(seen_path, encoding="utf-8")
                         if l.strip() and not l.strip().startswith("#")]

    after = hashlib.sha256(open(pkg, "rb").read()).hexdigest()

    result = Result(tmp=tmp, profile=profile, packages_seen=packages_seen,
                    returncode=proc.returncode, stdout=proc.stdout,
                    stderr=proc.stderr, tracked_file_unchanged=(before == after),
                    profile_arg=_CACHE.get("profile_arg"))
    _CACHE["result"] = result
    return result


def _teardown():
    if "tmp" in _CACHE:
        shutil.rmtree(_CACHE["tmp"], ignore_errors=True)


def test_build_succeeds():
    r = run_build()
    assert r.returncode == 0, f"exit {r.returncode}\nstdout: {r.stdout}\nstderr: {r.stderr}"


def test_mkarchiso_gets_the_repo_profile_not_scripts_dir():
    """The exact regression: the profile dir must not resolve to scripts/."""
    r = run_build()
    assert r.profile_arg, "mkarchiso was never invoked"
    assert not r.profile_arg.rstrip("/").endswith("/scripts"), \
        f"profile dir resolved to the scripts/ directory: {r.profile_arg}"
    assert r.profile_arg.rstrip("/").endswith("profile"), \
        f"mkarchiso was handed an unexpected profile dir: {r.profile_arg}"


def test_staged_profile_is_a_complete_archiso_profile():
    r = run_build()
    assert r.profile and os.path.isdir(r.profile), "no staged profile was preserved"
    for required in ("profiledef.sh", "pacman.conf", "packages.x86_64", "airootfs"):
        assert os.path.exists(os.path.join(r.profile, required)), \
            f"staged profile is missing {required} - mkarchiso cannot build from it"


def test_staged_profile_carries_the_desktop():
    r = run_build()
    for needed in ("root/.config/sway/config",
                   "root/.config/sway/scripts/perf-profile.sh",
                   "root/.config/sway/scripts/start-dock.sh",
                   "root/.config/waybar/config",
                   "root/.config/waybar/dock.jsonc",
                   "root/.config/mako/config",
                   "usr/share/icons/MarcusMix/index.theme",
                   "etc/systemd/zram-generator.conf"):
        assert os.path.isfile(os.path.join(r.profile, "airootfs", needed)), \
            f"airootfs/{needed} did not make it into the staged profile"


def test_staged_profile_excludes_the_vcs():
    r = run_build()
    assert not os.path.exists(os.path.join(r.profile, ".git")), \
        "the staged profile contains .git - the ISO would carry your history"


def test_vm_guest_tools_are_merged():
    r = run_build()
    assert "open-vm-tools" in r.packages_seen, \
        "the VM build did not add open-vm-tools - the merge into the staged list failed"
    assert "qemu-guest-agent" in r.packages_seen
    assert "sway" in r.packages_seen, "base package list was lost during the merge"


def test_committed_package_list_has_no_vm_tools():
    """The tracked file must stay a clean, real-hardware manifest."""
    pkgs = [l.strip() for l in open(os.path.join(ROOT, "packages.x86_64"), encoding="utf-8")
            if l.strip() and not l.strip().startswith("#")]
    for vm_only in ("open-vm-tools", "virtualbox-guest-utils-nox", "qemu-guest-agent"):
        assert vm_only not in pkgs, f"{vm_only} leaked into the committed packages.x86_64"


def test_tracked_package_list_is_untouched():
    r = run_build()
    assert r.tracked_file_unchanged, \
        "build-test-iso.sh MODIFIED the tracked packages.x86_64 - this is the " \
        "append-and-restore behaviour the staging rewrite exists to prevent"


def test_no_scratch_files_left_behind():
    run_build()
    leftovers = [f for f in os.listdir(ROOT) if f.startswith("packages.x86_64.")]
    assert not leftovers, f"scratch files left in the repo root: {leftovers}"
    assert "out" not in os.listdir(os.path.join(ROOT, "scripts")), \
        "build output went into scripts/ instead of the repo-root out/"


TESTS = [
    test_build_succeeds,
    test_mkarchiso_gets_the_repo_profile_not_scripts_dir,
    test_staged_profile_is_a_complete_archiso_profile,
    test_staged_profile_carries_the_desktop,
    test_staged_profile_excludes_the_vcs,
    test_vm_guest_tools_are_merged,
    test_committed_package_list_has_no_vm_tools,
    test_tracked_package_list_is_untouched,
    test_no_scratch_files_left_behind,
]

if __name__ == "__main__":
    try:
        main(TESTS)
    finally:
        _teardown()
