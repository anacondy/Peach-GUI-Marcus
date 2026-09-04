"""Tiny zero-dependency test runner.

The build host is an Arch system that may well not have pytest installed, and
adding a Python dependency to a repo whose only runtime is a shell script and a
compositor config is a bad trade. So: plain asserts, plain functions, this file.

Each test module exposes TESTS = [fn, ...] and calls run(TESTS) under __main__.
A failing test prints its assertion message and the runner exits 1, so
`tests/run-tests.sh` can be dropped straight into CI.
"""
import sys
import traceback


def run(tests, name=None):
    name = name or sys.argv[0].rsplit("/", 1)[-1]
    passed = failed = 0
    failures = []
    for fn in tests:
        label = fn.__name__.replace("test_", "", 1)
        try:
            fn()
        except AssertionError as e:
            failed += 1
            failures.append((label, str(e) or "assertion failed"))
            print(f"  FAIL  {label}")
            print(f"        {e}")
        except Exception:
            failed += 1
            failures.append((label, "unexpected exception"))
            print(f"  ERROR {label}")
            traceback.print_exc(limit=4)
        else:
            passed += 1
            print(f"  ok    {label}")
    print(f"\n  {name}: {passed} passed, {failed} failed")
    return 1 if failed else 0


def main(tests):
    sys.exit(run(tests))
