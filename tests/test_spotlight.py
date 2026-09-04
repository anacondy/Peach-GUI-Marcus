"""Functional test for ~/.config/sway/scripts/spotlight.sh.

Runs the REAL launcher against a fabricated $HOME with stub implementations of
updatedb, plocate, wofi, notify-send and xdg-open. wofi is stubbed to echo a
chosen line back, so the full path - index build, candidate assembly, selection,
dispatch - is exercised end to end.
"""
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _harness import main  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "airootfs/root/.config/sway/scripts/spotlight.sh")

DESKTOP_FILES = {
    "kitty.desktop": "[Desktop Entry]\nName=Kitty Terminal\nExec=kitty\nType=Application\n",
    "pcmanfm.desktop": "[Desktop Entry]\nName=Files\nExec=pcmanfm %U\nType=Application\n",
    "hidden.desktop": "[Desktop Entry]\nName=Should Not Appear\nExec=nope\nNoDisplay=true\n",
    # A percent sign that is NOT a field code. The old blanket 's/%[a-zA-Z]//g'
    # strip ate this and silently mangled the command line.
    "percent.desktop": "[Desktop Entry]\nName=Sleep Half\nExec=sh -c 'sleep 0.5s; echo 100%done'\nType=Application\n",
}
# Relative to $HOME, so Env can materialise them under the throwaway home.
INDEXED_RELPATHS = ["Documents/report.md", "Pictures/dog.png", "vanished.txt"]


class Env:
    def __init__(self, wofi_behaviour="pick-first", preseed_db=True):
        self.dir = tempfile.mkdtemp(prefix="spotlight-test.")
        self.home = os.path.join(self.dir, "home")
        self.bin = os.path.join(self.dir, "bin")
        self.launch_log = os.path.join(self.dir, "launched.log")
        os.makedirs(self.bin)
        os.makedirs(os.path.join(self.home, ".local/share/applications"))
        os.makedirs(os.path.join(self.home, ".cache/marcus-spotlight"))

        for name, body in DESKTOP_FILES.items():
            with open(os.path.join(self.home, ".local/share/applications", name), "w") as fh:
                fh.write(body)
        os.makedirs(os.path.join(self.home, "Documents"))
        open(os.path.join(self.home, "Documents/report.md"), "w").close()
        os.makedirs(os.path.join(self.home, "Pictures"))
        open(os.path.join(self.home, "Pictures/dog.png"), "w").close()
        # vanished.txt is deliberately in the index but not on disk: the
        # launcher must not offer a path that no longer exists.

        # Absolute paths under THIS throwaway home: spotlight.sh drops index
        # entries whose path no longer exists, so they have to be real.
        indexed = [os.path.join(self.home, rp) for rp in INDEXED_RELPATHS]

        if preseed_db:
            # spotlight.sh rebuilds the index in the background and searches
            # whatever index already exists, so a cold start has no file entries
            # by design. Seeding a fresh database lets these tests assert on the
            # search path deterministically instead of racing the rebuild.
            with open(self.db_file, "w", encoding="utf-8") as fh:
                fh.write("\n".join(indexed) + "\n")
            os.chmod(self.db_file, 0o600)

        lines = ["#!/bin/bash", 'out=""',
                 'while [[ $# -gt 0 ]]; do [[ "$1" == "--output" ]] && out="$2"; shift; done',
                 ': > "$out"']
        lines += [f'printf "%s\\n" "{p}" >> "$out"' for p in indexed]
        self._stub("updatedb", "\n".join(lines) + "\n")

        self._stub("plocate", "\n".join([
            "#!/bin/bash",
            "# Mimic `plocate -d DB -i PATTERN` by dumping the database.",
            'db=""',
            'while [[ $# -gt 0 ]]; do [[ "$1" == "-d" ]] && db="$2"; shift; done',
            'cat "$db"',
        ]) + "\n")

        if wofi_behaviour == "pick-first":
            # `IFS= read` matters: candidate lines begin with a space, and a bare
            # `read` would strip it and hand back a string that matches nothing.
            body = "#!/bin/bash\nIFS= read -r line\nprintf '%s\\n' \"$line\"\n"
        elif wofi_behaviour == "escape":
            # Escape dismisses wofi, which exits 1.
            body = "#!/bin/bash\ncat >/dev/null\nexit 1\n"
        else:
            body = "#!/bin/bash\ncat >/dev/null\nexit 0\n"
        self._stub("wofi", body)
        self._stub("notify-send", "#!/bin/bash\nexit 0\n")
        self._stub("xdg-open", f'#!/bin/bash\necho "xdg-open $1" >> "{self.launch_log}"\n')
        self._stub("setsid", f'#!/bin/bash\nshift\necho "run $*" >> "{self.launch_log}"\n')

        self.env = dict(os.environ)
        self.env["PATH"] = self.bin + os.pathsep + self.env["PATH"]
        self.env["HOME"] = self.home
        # Pin the .desktop search to the fixture. Without this the real
        # /usr/share/applications on the test machine leaks in and "the first
        # entry" stops being deterministic.
        self.env["MARCUS_APP_DIRS"] = os.path.join(self.home, ".local/share/applications")

    def _stub(self, name, body):
        p = os.path.join(self.bin, name)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(body)
        os.chmod(p, os.stat(p).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

    @property
    def map_file(self):
        return os.path.join(self.home, ".cache/marcus-spotlight/entries.tsv")

    @property
    def db_file(self):
        return os.path.join(self.home, ".cache/marcus-spotlight/home.db")

    def map_text(self):
        with open(self.map_file, encoding="utf-8") as fh:
            return fh.read()

    def run(self):
        return subprocess.run(["bash", SCRIPT], env=self.env, capture_output=True,
                              text=True, timeout=60)

    def launches(self):
        if not os.path.isfile(self.launch_log):
            return []
        with open(self.launch_log, encoding="utf-8") as fh:
            return [l.strip() for l in fh if l.strip()]

    def wait_for_launch(self, timeout=5.0):
        # The launcher detaches the selected command, so the log lands shortly
        # after the script returns.
        deadline = time.time() + timeout
        while time.time() < deadline:
            got = self.launches()
            if got:
                return got
            time.sleep(0.05)
        return []

    def cleanup(self):
        shutil.rmtree(self.dir, ignore_errors=True)


def test_map_contains_apps():
    env = Env()
    try:
        env.run()
        text = env.map_text()
        for name in ("Kitty Terminal", "Files", "Sleep Half"):
            assert name in text, f"{name!r} missing from the candidate list"
    finally:
        env.cleanup()


def test_nodisplay_entries_are_excluded():
    env = Env()
    try:
        env.run()
        assert "Should Not Appear" not in env.map_text(), \
            "a NoDisplay=true entry leaked into the launcher"
    finally:
        env.cleanup()


def test_field_codes_are_stripped_but_percent_signs_survive():
    env = Env()
    try:
        env.run()
        text = env.map_text()
        assert "pcmanfm" in text, "pcmanfm missing from the candidate list"
        assert "%U" not in text, f"the %U field code was not stripped:\n{text}"
        assert "100%done" in text, \
            f"a literal percent sign was mangled by field-code stripping:\n{text}"
    finally:
        env.cleanup()


def test_indexed_files_appear_and_missing_ones_do_not():
    env = Env()
    try:
        env.run()
        text = env.map_text()
        assert "report.md" in text, "an indexed, existing file is missing"
        assert "dog.png" in text
        assert "vanished.txt" not in text, \
            "a path that is in the index but not on disk was offered to the user"
    finally:
        env.cleanup()


def test_selecting_an_app_runs_it():
    env = Env()
    try:
        proc = env.run()
        assert proc.returncode == 0, f"exit {proc.returncode}\n{proc.stderr}"
        # wofi echoes the FIRST line, which is the first application entry.
        got = env.wait_for_launch()
        assert any(l.startswith("run ") for l in got), \
            f"selecting an entry launched nothing: {got}"
    finally:
        env.cleanup()


def test_dismissing_with_escape_is_not_an_error():
    """wofi exits 1 on Escape; `set -e` used to tear the script down there."""
    env = Env(wofi_behaviour="escape")
    try:
        proc = env.run()
        assert proc.returncode == 0, \
            f"dismissing the launcher exited {proc.returncode}: {proc.stderr}"
        assert env.launches() == [], "dismissing the launcher launched something"
    finally:
        env.cleanup()


def test_index_database_is_private():
    """--require-visibility 0 indexes files regardless of directory permissions,
    so the database is a complete map of the user's home. It must be mode 600."""
    env = Env(preseed_db=False)
    try:
        env.run()
        deadline = time.time() + 5
        while time.time() < deadline and not os.path.isfile(env.db_file):
            time.sleep(0.05)
        assert os.path.isfile(env.db_file), "the index database was never created"
        mode = oct(os.stat(env.db_file).st_mode & 0o777)
        assert mode == "0o600", f"index database is {mode}, expected 0600"
    finally:
        env.cleanup()


def test_cold_start_still_lists_apps():
    """With no index yet, the launcher must still work - apps only, no files."""
    env = Env(preseed_db=False)
    try:
        proc = env.run()
        assert proc.returncode == 0, f"cold start exited {proc.returncode}: {proc.stderr}"
        assert "Kitty Terminal" in env.map_text(), "cold start produced no app entries"
    finally:
        env.cleanup()


def test_candidate_list_is_cached():
    """The whole point of the cache: a second open must not re-scan the home."""
    env = Env()
    try:
        env.run()
        first = os.stat(env.map_file).st_mtime_ns
        env.run()
        time.sleep(0.1)
        second = os.stat(env.map_file).st_mtime_ns
        assert first == second, \
            "the candidate list was rebuilt on the second invocation despite being fresh"
    finally:
        env.cleanup()


TESTS = [
    test_map_contains_apps,
    test_nodisplay_entries_are_excluded,
    test_field_codes_are_stripped_but_percent_signs_survive,
    test_indexed_files_appear_and_missing_ones_do_not,
    test_selecting_an_app_runs_it,
    test_dismissing_with_escape_is_not_an_error,
    test_index_database_is_private,
    test_cold_start_still_lists_apps,
    test_candidate_list_is_cached,
]

if __name__ == "__main__":
    main(TESTS)
