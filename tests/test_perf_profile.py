"""Functional test for scripts/perf-profile.sh.

This runs the REAL script. The only thing substituted is `swaymsg`, which is
replaced with a shell stub that serves canned `get_outputs` JSON and records the
`output ... max_render_time` commands it is asked to run. So what is under test
is the actual tier logic, the actual arithmetic and the actual generated
effects.conf - not a reimplementation of them.

This is the only way to test any of it here: there is no compositor, no display
server and no GPU in this environment.
"""
import json
import os
import stat
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _harness import main  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "airootfs/root/.config/sway/scripts/perf-profile.sh")

# name, width, height, refresh in MILLIHz (what sway's IPC actually reports)
OUTPUTS = {
    "1080p60":   [("eDP-1", 1920, 1080, 60000)],
    "1080p144":  [("eDP-1", 1920, 1080, 144000)],
    "1440p120":  [("DP-1", 2560, 1440, 120000)],
    "4k60":      [("HDMI-A-1", 3840, 2160, 60000)],
    "4k144":     [("DP-1", 3840, 2160, 144000)],
    "dual4k144": [("DP-1", 3840, 2160, 144000), ("DP-2", 3840, 2160, 144000)],
    "240hz":     [("DP-1", 1920, 1080, 240000)],
    "30hz":      [("HDMI-A-1", 3840, 2160, 30000)],
    "90hz":      [("eDP-1", 2880, 1800, 90000)],
}


class Env:
    """A throwaway world for one perf-profile.sh invocation."""

    def __init__(self, scenario, swayfx=True, renderer=None, drm=True):
        self.dir = tempfile.mkdtemp(prefix="perf-test.")
        self.home = os.path.join(self.dir, "home")
        os.makedirs(os.path.join(self.home, ".config/sway"))
        os.makedirs(os.path.join(self.home, ".cache"))
        self.effects = os.path.join(self.home, ".config/sway/effects.conf")
        self.state = os.path.join(self.home, ".cache/perf-state")
        self.calls_log = os.path.join(self.dir, "swaymsg-calls.log")
        open(self.calls_log, "w").close()

        outs = [
            {"name": n, "active": True,
             "rect": {"x": 0, "y": 0, "width": w, "height": h},
             "current_mode": {"width": w, "height": h, "refresh": r},
             "scale": 1.0}
            for (n, w, h, r) in OUTPUTS[scenario]
        ]
        version = "1.10-swayfx" if swayfx else "1.10"

        stub = os.path.join(self.dir, "swaymsg")
        with open(stub, "w", encoding="utf-8") as fh:
            fh.write(f"""#!/bin/bash
# Test stub standing in for swaymsg. Serves canned IPC and records mutations.
args="$*"
case "$args" in
  *"-t get_outputs"*) cat <<'JSON'
{json.dumps(outs)}
JSON
      ;;
  *"-t get_version"*) echo "{version}" ;;
  *) echo "$args" >> "{self.calls_log}" ;;
esac
exit 0
""")
        os.chmod(stub, os.stat(stub).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

        self.env = dict(os.environ)
        self.env.update({
            "HOME": self.home,
            "SWAYMSG": stub,
            "MARCUS_EFFECTS_CONF": self.effects,
            "MARCUS_PERF_STATE": self.state,
            "MARCUS_DRM_GLOB": (os.path.join(self.dir, "drm-card*") if drm else "/nonexistent/dri/card*"),
        })
        self.env.pop("WLR_RENDERER", None)
        if renderer:
            self.env["WLR_RENDERER"] = renderer
        if drm:
            open(os.path.join(self.dir, "drm-card0"), "w").close()

    def run(self, *args):
        proc = subprocess.run(["bash", SCRIPT, *args], env=self.env,
                              capture_output=True, text=True, timeout=30)
        assert proc.returncode == 0, \
            f"perf-profile.sh exited {proc.returncode}\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
        return proc.stdout

    def effects_text(self):
        return open(self.effects, encoding="utf-8").read()

    def calls(self):
        with open(self.calls_log, encoding="utf-8") as fh:
            return [l.strip() for l in fh if l.strip()]

    def cleanup(self):
        import shutil
        shutil.rmtree(self.dir, ignore_errors=True)


def _render_time(scenario):
    """Pull the max_render_time the script asked sway to set."""
    env = Env(scenario)
    try:
        env.run()
        times = {}
        for call in env.calls():
            parts = call.split()
            if "max_render_time" in parts:
                times[parts[1]] = int(parts[-1])
        return times, env.effects_text()
    finally:
        env.cleanup()


# --- max_render_time -------------------------------------------------------
# interval - 4ms headroom, rounded, clamped to [1, 16].
def test_render_time_60hz():
    times, _ = _render_time("1080p60")
    assert times == {"eDP-1": 13}, f"1080p@60 -> {times}, expected eDP-1:13 (16.7-4=12.7)"


def test_render_time_90hz():
    times, _ = _render_time("90hz")
    assert times == {"eDP-1": 7}, f"2880x1800@90 -> {times}, expected eDP-1:7 (11.1-4=7.1)"


def test_render_time_120hz():
    times, _ = _render_time("1440p120")
    assert times == {"DP-1": 4}, f"1440p@120 -> {times}, expected DP-1:4 (8.3-4=4.3)"


def test_render_time_144hz():
    times, _ = _render_time("1080p144")
    assert times == {"eDP-1": 3}, f"1080p@144 -> {times}, expected eDP-1:3 (6.9-4=2.9)"


def test_render_time_240hz_is_clamped_low():
    times, _ = _render_time("240hz")
    assert times == {"DP-1": 1}, f"1080p@240 -> {times}, expected floor clamp to 1ms"


def test_render_time_30hz_is_clamped_high():
    times, _ = _render_time("30hz")
    assert times == {"HDMI-A-1": 16}, f"4K@30 -> {times}, expected ceiling clamp to 16"


def test_render_time_is_per_output():
    """A mixed setup must not get one number for both panels."""
    env = Env("dual4k144")
    try:
        env.run()
        names = {c.split()[1] for c in env.calls() if "max_render_time" in c}
        assert names == {"DP-1", "DP-2"}, f"per-output commands: {env.calls()}"
    finally:
        env.cleanup()


# --- quality tiers ---------------------------------------------------------
def _tier(scenario, **kw):
    env = Env(scenario, **kw)
    try:
        env.run()
        text = env.effects_text()
        for line in text.splitlines():
            if line.startswith("// tier="):
                # "// tier=high  max_refresh=60Hz  ..." -> split()[1] is "tier=high"
                return line.split()[1].split("=", 1)[1], text
        raise AssertionError(f"no tier line in generated effects.conf:\n{text}")
    finally:
        env.cleanup()


def test_tier_high_on_the_target_laptop():
    tier, text = _tier("1080p60")
    assert tier == "high", f"1080p@60 (the HP 14s case) got tier {tier}, expected high"
    # The high tier must be the previous inline config, unchanged - the whole
    # point is that this refactor does not alter the look.
    for directive in ("blur_passes 2", "blur_radius 3", "blur_noise 0.02",
                      "shadow_blur_radius 18", "corner_radius 10"):
        assert directive in text, f"high tier lost '{directive}'"


def test_tier_balanced_on_4k60():
    tier, _ = _tier("4k60")
    assert tier == "balanced", f"4K@60 (498MP/s) got {tier}, expected balanced"


def test_tier_light_on_4k144():
    tier, _ = _tier("4k144")
    assert tier == "light", f"4K@144 (1195MP/s) got {tier}, expected light"


def test_tier_off_on_dual_4k144():
    tier, _ = _tier("dual4k144")
    assert tier == "off", f"dual 4K@144 (2390MP/s) got {tier}, expected off"


def test_tier_high_survives_1080p_at_144():
    tier, _ = _tier("1080p144")
    assert tier == "high", f"1080p@144 (298MP/s) got {tier}; a high-refresh 1080p panel should not be derated"


def test_software_renderer_disables_effects():
    tier, text = _tier("1080p60", renderer="pixman")
    assert tier == "off", f"pixman renderer got tier {tier}, expected off"
    assert "blur disable" in text


def test_no_gpu_disables_effects():
    tier, _ = _tier("1080p60", drm=False)
    assert tier == "off", f"no DRM node got tier {tier}, expected off"


# --- SwayFX gating ---------------------------------------------------------
def test_vanilla_sway_gets_a_comments_only_include():
    env = Env("1080p60", swayfx=False)
    try:
        env.run()
        text = env.effects_text()
        directives = [l for l in text.splitlines()
                      if l.strip() and not l.strip().startswith("//")]
        assert directives == [], \
            f"vanilla sway got live directives it will error on: {directives}"
    finally:
        env.cleanup()


def test_swayfx_gets_live_directives():
    env = Env("1080p60", swayfx=True)
    try:
        env.run()
        text = env.effects_text()
        assert "blur enable" in text and "shadows enable" in text, \
            f"SwayFX present but no effect directives generated:\n{text}"
    finally:
        env.cleanup()


# --- idempotency -----------------------------------------------------------
def test_second_run_is_a_no_op():
    """Reload must not reconfigure every output when nothing changed."""
    env = Env("1080p60")
    try:
        env.run()
        first = env.calls()
        assert first, "first run should have applied max_render_time"
        open(env.calls_log, "w").close()
        out = env.run()
        assert env.calls() == [], \
            f"second identical run re-issued: {env.calls()}"
        assert "unchanged" in out, f"expected an 'unchanged' log line, got: {out!r}"
    finally:
        env.cleanup()


def test_prestart_does_not_call_swaymsg():
    """The .zprofile pass has no socket; it must not try to use one."""
    env = Env("1080p60")
    try:
        env.run("--prestart")
        assert env.calls() == [], f"--prestart issued swaymsg mutations: {env.calls()}"
        assert os.path.isfile(env.effects), "--prestart did not write effects.conf"
    finally:
        env.cleanup()


def test_override_env_forces_a_tier():
    env = Env("1080p60")
    try:
        env.env["MARCUS_PERF_TIER"] = "off"
        env.run()
        assert "blur disable" in env.effects_text()
    finally:
        env.cleanup()


TESTS = [
    test_render_time_60hz,
    test_render_time_90hz,
    test_render_time_120hz,
    test_render_time_144hz,
    test_render_time_240hz_is_clamped_low,
    test_render_time_30hz_is_clamped_high,
    test_render_time_is_per_output,
    test_tier_high_on_the_target_laptop,
    test_tier_balanced_on_4k60,
    test_tier_light_on_4k144,
    test_tier_off_on_dual_4k144,
    test_tier_high_survives_1080p_at_144,
    test_software_renderer_disables_effects,
    test_no_gpu_disables_effects,
    test_vanilla_sway_gets_a_comments_only_include,
    test_swayfx_gets_live_directives,
    test_second_run_is_a_no_op,
    test_prestart_does_not_call_swaymsg,
    test_override_env_forces_a_tier,
]

if __name__ == "__main__":
    main(TESTS)
