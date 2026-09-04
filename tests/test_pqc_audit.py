"""Smoke test for scripts/pqc-audit.

Runs the real scanner on this machine. The findings themselves are not asserted
on - a container is not a representative target and its OpenSSL version, key
inventory and disk layout say nothing about the ISO. What IS asserted is that the
tool runs to completion, covers every subsystem it claims to, emits valid JSON
in machine-readable mode, and degrades instead of crashing when a tool is absent.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _harness import main  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "scripts/pqc-audit")

EXPECTED_AREAS = {"ssh-kex", "ssh-identity", "gpg", "tls-openssl",
                  "disk", "pkg-signing", "secure-boot", "liboqs"}
VALID_STATUS = {"protected", "hybrid", "partial", "exposed", "unknown"}


def _run(*args, env_extra=None):
    env = dict(os.environ)
    if env_extra:
        env.update(env_extra)
    return subprocess.run(["bash", SCRIPT, *args], capture_output=True,
                          text=True, timeout=120, env=env,
                          # Absolute interpreter path: one test empties PATH on
                          # purpose, and the shell has to survive that.
                          executable="/bin/bash")


def test_runs_clean():
    proc = _run()
    assert proc.returncode == 0, f"exit {proc.returncode}\n{proc.stderr}"
    assert "pqc-audit" in proc.stdout


def test_covers_every_subsystem():
    proc = _run("--json")
    assert proc.returncode == 0, proc.stderr
    data = json.loads(proc.stdout)
    ids = {f["id"] for f in data["findings"]}
    missing = EXPECTED_AREAS - ids
    assert not missing, f"pqc-audit no longer reports on: {sorted(missing)}"


def test_json_is_well_formed():
    proc = _run("--json")
    data = json.loads(proc.stdout)
    assert "host" in data and "date" in data
    for f in data["findings"]:
        assert f["status"] in VALID_STATUS, f"{f['id']} has status {f['status']!r}"
        assert f["detail"], f"{f['id']} has an empty detail string"


def test_date_is_day_month_year():
    """The report header should use the same date format as the rest of the project."""
    import re
    proc = _run("--json")
    data = json.loads(proc.stdout)
    assert re.match(r"^\d{2} [A-Z][a-z]+ \d{4},", data["date"]), \
        f"date {data['date']!r} is not 'DD Month YYYY, ...'"


def test_summary_line_present_in_text_mode():
    proc = _run()
    assert "protected/hybrid:" in proc.stdout, \
        f"no summary line in text output:\n{proc.stdout[-800:]}"


def test_degrades_without_ssh():
    """A machine without openssh must produce an 'unknown', not a stack trace."""
    env = {"PATH": "/nonexistent-path-for-testing"}
    proc = _run(env_extra=env)
    assert proc.returncode == 0, f"exit {proc.returncode}\n{proc.stderr}"
    assert "unknown" in proc.stdout


def test_strict_mode_reflects_findings():
    """--strict exits non-zero when something scores 'exposed'.

    Asserted as a relationship rather than a fixed exit code, because whether
    anything IS exposed depends on the machine.
    """
    report = json.loads(_run("--json").stdout)
    exposed = [f for f in report["findings"] if f["status"] == "exposed"]
    strict = _run("--strict")
    if exposed:
        assert strict.returncode != 0, \
            f"{len(exposed)} exposed finding(s) but --strict exited 0"
    else:
        assert strict.returncode == 0, "no exposed findings but --strict exited non-zero"


TESTS = [
    test_runs_clean,
    test_covers_every_subsystem,
    test_json_is_well_formed,
    test_date_is_day_month_year,
    test_summary_line_present_in_text_mode,
    test_degrades_without_ssh,
    test_strict_mode_reflects_findings,
]

if __name__ == "__main__":
    main(TESTS)
