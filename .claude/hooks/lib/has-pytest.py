#!/usr/bin/env python3
# Exit 0 when pytest is importable in the project's Python, else 1. Run by lib/tests.sh to decide the
# test command (ADR-0018 moved it out of an inline `python3 -c` so the directory validator can follow
# the plugin's commands). "No module named pytest" is not a red suite, so this is found, not imported;
# and never from the current directory or this script's own directory, so a pytest.py a repository (or
# the plugin) ships cannot stand in for the real one.
import sys

sys.path[:] = [p for p in sys.path if p not in ("", ".", sys.path[0])]
import importlib.util  # noqa: E402  (after the sys.path scrub, on purpose)

sys.exit(importlib.util.find_spec("pytest") is None)
